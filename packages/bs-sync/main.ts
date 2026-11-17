// Gets Beat Saber custom levels onto a standalone headset (the Steam Frame) over
// ssh. The unmodded game reads any folder under CustomLevels/, so this only has
// to put map folders in place. Playlists are also written to Playlists/ so they
// work once PlaylistManager is installed.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, extname, join } from "node:path";
import { parseArgs } from "node:util";

const GAME_DIR = ".local/share/Steam/steamapps/common/Beat Saber";
const LEVELS_DIR = `${GAME_DIR}/Beat Saber_Data/CustomLevels`;
const PLAYLISTS_DIR = `${GAME_DIR}/Playlists`;
const API = "https://api.beatsaver.com";

type Track = { title: string; artists: string[]; durationS: number | null };
type PlaylistInput =
  | { kind: "tracks"; name: string; tracks: Track[] }
  | { kind: "maps"; name: string; refs: MapRef[] };
type MapRef = { by: "hash"; hash: string } | { by: "key"; key: string };

type BsMap = {
  id: string;
  name: string;
  automapper: boolean;
  metadata: { songName: string; songSubName: string; songAuthorName: string; levelAuthorName: string; duration: number };
  stats: { score: number; upvotes: number };
  versions: { hash: string; downloadURL: string; state: string }[];
};
type Match = { track: Track; result: { kind: "found"; map: BsMap } | { kind: "missing" } };

const usage = `usage:
  bs-sync playlist <exportify.csv | file.bplist> [--min-rating 0.7] [--dry-run]
  bs-sync key <beatsaver key>...
  bs-sync push <map folder | zip | folder of maps>...
options:
  --host <user@host>   default steamos@frame (or $BS_SYNC_HOST)`;

// ---------- remote ----------

function run(cmd: string, args: string[], input?: string): string {
  const r = spawnSync(cmd, args, { encoding: "utf8", input, stdio: ["pipe", "pipe", "inherit"] });
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(" ")} exited ${r.status}`);
  return r.stdout;
}

function remoteLevelKeys(host: string): Set<string> {
  // The remote side goes through a shell, so the path is single-quoted there.
  const out = run("ssh", [host, `mkdir -p '${LEVELS_DIR}' '${PLAYLISTS_DIR}' && ls -1 '${LEVELS_DIR}'`]);
  // Folders BeatSaver tools create are "<key> (<song> - <mapper>)"; hand-made ones don't
  // have a key and are simply never treated as duplicates.
  return new Set(out.split("\n").map((l) => l.split(" ")[0].toLowerCase()).filter(Boolean));
}

function rsyncInto(host: string, localDir: string, remoteDir: string): void {
  // Trailing slash: copy the contents of localDir. -s keeps the spaces in the remote
  // path intact (rsync >= 3.2.4 does this by default, older ones need the flag).
  run("rsync", ["-rt", "-s", "--info=stats1", `${localDir}/`, `${host}:${remoteDir}/`]);
}

// ---------- input parsing ----------

function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field); rows.push(row); row = []; field = "";
    } else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows.filter((r) => r.some((f) => f !== ""));
}

function readPlaylist(path: string): PlaylistInput {
  const name = basename(path, extname(path)).replace(/_/g, " ");
  const text = readFileSync(path, "utf8").replace(/^﻿/, "");
  if (extname(path).toLowerCase() === ".bplist") {
    const bp = JSON.parse(text) as { playlistTitle?: string; songs: { hash?: string; key?: string }[] };
    const refs = bp.songs.flatMap((s): MapRef[] =>
      s.hash ? [{ by: "hash", hash: s.hash.toLowerCase() }] : s.key ? [{ by: "key", key: s.key.toLowerCase() }] : [],
    );
    return { kind: "maps", name: bp.playlistTitle ?? name, refs };
  }
  // Exportify CSV: header row names the columns, so look them up instead of trusting positions.
  const [header, ...rows] = parseCsv(text);
  const col = (n: string) => {
    const i = header.indexOf(n);
    if (i < 0) throw new Error(`CSV has no "${n}" column; expected an Exportify export`);
    return i;
  };
  const [ti, ai, di] = [col("Track Name"), col("Artist Name(s)"), col("Duration (ms)")];
  const tracks = rows.map((r) => ({
    title: r[ti],
    artists: r[ai].split(";").map((a) => a.trim()).filter(Boolean),
    durationS: Number(r[di]) / 1000 || null,
  }));
  return { kind: "tracks", name, tracks };
}

// ---------- matching ----------

// Strip decoration that differs between Spotify and map metadata:
// "(feat. X)", "[Remastered]", " - 2011 Remaster", accents, punctuation.
function norm(s: string): string {
  return s
    .normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[([].*?[)\]]/g, " ")
    .replace(/\s-\s.*(remaster|version|edit|mix|live|mono|stereo).*$/, " ")
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

const containsWords = (hay: string, needle: string) => needle !== "" && ` ${hay} `.includes(` ${needle} `);

async function api<T>(path: string): Promise<T | null> {
  for (let attempt = 0; attempt < 4; attempt++) {
    const res = await fetch(`${API}${path}`, { headers: { "user-agent": "bs-sync" } });
    if (res.status === 404) return null;
    if (res.status === 429 || res.status >= 500) { await sleep(1000 * 2 ** attempt); continue; }
    if (!res.ok) throw new Error(`BeatSaver ${path}: HTTP ${res.status}`);
    return (await res.json()) as T;
  }
  throw new Error(`BeatSaver ${path}: gave up after retries`);
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function isMatch(track: Track, m: BsMap, minRating: number): boolean {
  if (m.automapper || m.stats.score < minRating) return false;
  if (!m.versions.some((v) => v.state === "Published")) return false;
  const title = norm(track.title);
  // Mappers put the artist in songName or the map name about as often as in songAuthorName.
  const songText = norm(`${m.metadata.songName} ${m.metadata.songSubName} ${m.name}`);
  const artistText = norm(`${m.metadata.songAuthorName} ${m.metadata.songName} ${m.name}`);
  return containsWords(songText, title) && track.artists.some((a) => containsWords(artistText, norm(a)));
}

function rank(track: Track, m: BsMap): number {
  // Full-length maps of the right song beat cut versions and same-named covers;
  // past that, the community rating decides.
  const closeLength = track.durationS == null || Math.abs(m.metadata.duration - track.durationS) <= 20;
  return (closeLength ? 1 : 0) + m.stats.score;
}

async function findMap(track: Track, minRating: number): Promise<BsMap | null> {
  const queries = [`${norm(track.title)} ${norm(track.artists[0] ?? "")}`, norm(track.title)];
  for (const q of queries) {
    const res = await api<{ docs: BsMap[] }>(`/search/text/0?q=${encodeURIComponent(q)}&sortOrder=Relevance`);
    const hits = (res?.docs ?? []).filter((m) => isMatch(track, m, minRating));
    if (hits.length) return hits.sort((a, b) => rank(track, b) - rank(track, a))[0];
  }
  return null;
}

// ---------- download ----------

const folderName = (m: BsMap) =>
  `${m.id} (${m.metadata.songName} - ${m.metadata.levelAuthorName})`.replace(/[\\/:*?"<>|]/g, "");

async function downloadInto(m: BsMap, stage: string): Promise<void> {
  const v = m.versions.find((v) => v.state === "Published") ?? m.versions[0];
  const res = await fetch(v.downloadURL);
  if (!res.ok) throw new Error(`download ${m.id}: HTTP ${res.status}`);
  const zip = join(stage, `${m.id}.zip`);
  writeFileSync(zip, Buffer.from(await res.arrayBuffer()));
  run("unzip", ["-q", "-o", zip, "-d", join(stage, "levels", folderName(m))]);
}

function bplist(name: string, maps: BsMap[]): string {
  return JSON.stringify({
    playlistTitle: name,
    playlistAuthor: "bs-sync",
    songs: maps.map((m) => ({ key: m.id, hash: m.versions[0].hash, songName: m.metadata.songName })),
  }, null, 2);
}

async function syncMaps(host: string, maps: BsMap[], playlistName: string | null, dryRun: boolean) {
  const existing = remoteLevelKeys(host);
  const fresh = maps.filter((m, i) => !existing.has(m.id.toLowerCase()) && maps.findIndex((x) => x.id === m.id) === i);
  console.log(`\n${maps.length} maps, ${maps.length - fresh.length} already on ${host}, ${fresh.length} to fetch`);
  if (dryRun) return;
  const stage = mkdtempSync(join(tmpdir(), "bs-sync-"));
  mkdirSync(join(stage, "levels"));
  for (const m of fresh) {
    process.stdout.write(`  downloading ${folderName(m)}\n`);
    await downloadInto(m, stage);
  }
  if (fresh.length) rsyncInto(host, join(stage, "levels"), LEVELS_DIR);
  if (playlistName) {
    mkdirSync(join(stage, "playlists"));
    const file = `${playlistName.replace(/[\\/:*?"<>|]/g, "")}.bplist`;
    writeFileSync(join(stage, "playlists", file), bplist(playlistName, maps));
    rsyncInto(host, join(stage, "playlists"), PLAYLISTS_DIR);
    console.log(`  wrote Playlists/${file}`);
  }
}

// ---------- commands ----------

async function cmdPlaylist(host: string, path: string, minRating: number, dryRun: boolean) {
  const input = readPlaylist(path);
  const maps: BsMap[] = [];
  if (input.kind === "maps") {
    for (const ref of input.refs) {
      const m = await api<BsMap>(ref.by === "hash" ? `/maps/hash/${ref.hash}` : `/maps/id/${ref.key}`);
      if (m) maps.push(m);
      else console.log(`  gone from BeatSaver: ${ref.by === "hash" ? ref.hash : ref.key}`);
    }
  } else {
    const matches: Match[] = [];
    for (const track of input.tracks) {
      const map = await findMap(track, minRating);
      matches.push({ track, result: map ? { kind: "found", map } : { kind: "missing" } });
      const label = `${track.artists.join(", ")} - ${track.title}`;
      console.log(map
        ? `  ✓ ${label}  →  ${map.id} by ${map.metadata.levelAuthorName} (${Math.round(map.stats.score * 100)}%)`
        : `  ✗ ${label}`);
    }
    for (const m of matches) if (m.result.kind === "found") maps.push(m.result.map);
  }
  await syncMaps(host, maps, input.name, dryRun);
}

async function cmdKeys(host: string, keys: string[]) {
  const maps: BsMap[] = [];
  for (const key of keys) {
    const m = await api<BsMap>(`/maps/id/${key.toLowerCase()}`);
    if (m) maps.push(m);
    else console.log(`  no map with key ${key}`);
  }
  await syncMaps(host, maps, null, false);
}

function cmdPush(host: string, paths: string[]) {
  const stage = mkdtempSync(join(tmpdir(), "bs-sync-"));
  const isLevel = (d: string) => existsSync(join(d, "Info.dat")) || existsSync(join(d, "info.dat"));
  const add = (src: string) => {
    if (statSync(src).isDirectory()) {
      if (isLevel(src)) run("cp", ["-r", src, join(stage, basename(src))]);
      else for (const child of readdirSync(src)) add(join(src, child));
    } else if (extname(src).toLowerCase() === ".zip") {
      run("unzip", ["-q", "-o", src, "-d", join(stage, basename(src, ".zip"))]);
    }
  };
  paths.forEach(add);
  const levels = readdirSync(stage);
  if (!levels.length) throw new Error("nothing that looks like a map (no Info.dat or .zip) in the given paths");
  remoteLevelKeys(host); // creates the target dirs
  rsyncInto(host, stage, LEVELS_DIR);
  console.log(`pushed ${levels.length} maps to ${host}`);
}

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    host: { type: "string", default: process.env.BS_SYNC_HOST ?? "steamos@frame" },
    "min-rating": { type: "string", default: "0.7" },
    "dry-run": { type: "boolean", default: false },
    help: { type: "boolean", short: "h", default: false },
  },
});
const [cmd, ...rest] = positionals;
const host = values.host!;
try {
  if (values.help || !cmd) console.log(usage);
  else if (cmd === "playlist" && rest.length === 1) await cmdPlaylist(host, rest[0], Number(values["min-rating"]), values["dry-run"]!);
  else if (cmd === "key" && rest.length) await cmdKeys(host, rest);
  else if (cmd === "push" && rest.length) cmdPush(host, rest);
  else { console.error(usage); process.exit(2); }
} catch (e) {
  console.error(`bs-sync: ${(e as Error).message}`);
  process.exit(1);
}
