// Speaks the slice of whisper-asr-webservice's API that Bazarr's whisperai
// provider uses (/asr and /detect-language), backed by a whisper.cpp server.
// whisper.cpp has its own /inference API, and whisper-asr-webservice would
// mean a second Python whisper stack next to the one we already run.
import { createServer, request, type IncomingMessage, type ServerResponse } from "node:http";
import { Readable } from "node:stream";

const listen = new URL(requiredEnv("SHIM_LISTEN"));
const backend = requiredEnv("WHISPER_URL");

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

type Task = "transcribe" | "translate";

function parseTask(raw: string | null): Task {
  if (raw === null || raw === "transcribe") return "transcribe";
  if (raw === "translate") return "translate";
  throw new HttpError(400, `unknown task ${raw}`);
}

class HttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

// Bazarr sends `encode=false` with the track already decoded by its own ffmpeg
// to 16 kHz mono s16le, headerless. whisper.cpp only reads containers, so the
// PCM gets the 44-byte WAV header it is missing.
function wavFromPcm(pcm: Uint8Array): Uint8Array {
  const sampleRate = 16000;
  const header = new DataView(new ArrayBuffer(44));
  const ascii = (offset: number, text: string) =>
    [...text].forEach((c, i) => header.setUint8(offset + i, c.charCodeAt(0)));
  ascii(0, "RIFF");
  header.setUint32(4, 36 + pcm.byteLength, true);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  header.setUint32(16, 16, true);
  header.setUint16(20, 1, true); // PCM
  header.setUint16(22, 1, true); // mono
  header.setUint32(24, sampleRate, true);
  header.setUint32(28, sampleRate * 2, true);
  header.setUint16(32, 2, true);
  header.setUint16(34, 16, true);
  ascii(36, "data");
  header.setUint32(40, pcm.byteLength, true);
  const wav = new Uint8Array(44 + pcm.byteLength);
  wav.set(new Uint8Array(header.buffer), 0);
  wav.set(pcm, 44);
  return wav;
}

async function audioFrom(req: IncomingMessage, url: URL): Promise<Uint8Array> {
  const form = await new Request(url, {
    method: "POST",
    headers: req.headers as HeadersInit,
    body: req as unknown as ReadableStream,
    duplex: "half",
  } as RequestInit).formData();
  const file = form.get("audio_file");
  if (!(file instanceof Blob)) throw new HttpError(400, "audio_file missing");
  const bytes = new Uint8Array(await file.arrayBuffer());
  return url.searchParams.get("encode") === "false" ? wavFromPcm(bytes) : bytes;
}

async function infer(audio: Uint8Array, fields: Record<string, string>): Promise<Response> {
  const form = new FormData();
  form.set("file", new Blob([audio], { type: "audio/wav" }), "audio.wav");
  for (const [k, v] of Object.entries(fields)) form.set(k, v);
  // Not fetch: undici gives up waiting for response headers after 300s, and
  // whisper.cpp sends none until it is done, which translating a 24-minute
  // episode takes longer than. node:http has no such default.
  const encoded = new Response(form);
  const contentType = encoded.headers.get("content-type");
  if (!contentType) throw new Error("FormData encoded without a content-type");
  const body = new Uint8Array(await encoded.arrayBuffer());
  const raw = await new Promise<IncomingMessage>((resolve, reject) =>
    request(
      `${backend}/inference`,
      { method: "POST", headers: { "content-type": contentType, "content-length": body.byteLength } },
      resolve,
    ).on("error", reject).end(body),
  );
  const res = new Response(Readable.toWeb(raw) as ReadableStream, { status: raw.statusCode });
  if (!res.ok) throw new HttpError(502, `whisper.cpp ${res.status}: ${await res.text()}`);
  return res;
}

async function asr(req: IncomingMessage, url: URL): Promise<[string, string]> {
  const output = url.searchParams.get("output") ?? "srt";
  if (output !== "srt" && output !== "vtt" && output !== "txt" && output !== "json") {
    throw new HttpError(400, `unsupported output ${output}`);
  }
  const task = parseTask(url.searchParams.get("task"));
  const res = await infer(await audioFrom(req, url), {
    response_format: output === "txt" ? "text" : output,
    language: url.searchParams.get("language") ?? "auto",
    translate: String(task === "translate"),
  });
  return [output === "json" ? "application/json" : "text/plain; charset=utf-8", await res.text()];
}

async function detectLanguage(req: IncomingMessage, url: URL): Promise<[string, string]> {
  // Detection only needs the opening of the track, and a whole episode would
  // tie the GPU up transcribing it just to read off the language.
  const audio = await audioFrom(req, url);
  const thirtySeconds = 44 + 16000 * 2 * 30;
  const res = await infer(audio.subarray(0, Math.min(audio.byteLength, thirtySeconds)), {
    response_format: "verbose_json",
    language: "auto",
  });
  const { language } = (await res.json()) as { language?: string };
  if (!language) throw new HttpError(502, "whisper.cpp returned no language");
  // whisper.cpp reports the full name ("english"), not the code. Bazarr tries
  // the code as alpha2 and falls back to parsing the name, so handing it the
  // name in both fields resolves without a code table here.
  const name = language[0].toUpperCase() + language.slice(1);
  return ["application/json", JSON.stringify({ detected_language: name, language_code: language })];
}

async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const url = new URL(req.url ?? "/", listen);
  try {
    if (req.method !== "POST") throw new HttpError(405, "POST only");
    const [type, body] =
      url.pathname === "/asr" ? await asr(req, url)
      : url.pathname === "/detect-language" ? await detectLanguage(req, url)
      : (() => { throw new HttpError(404, `no route ${url.pathname}`); })();
    res.writeHead(200, { "content-type": type }).end(body);
  } catch (err) {
    const status = err instanceof HttpError ? err.status : 500;
    console.error(`${req.method} ${url.pathname}: ${status} ${err}`);
    res.writeHead(status, { "content-type": "text/plain" }).end(String(err));
  }
}

createServer((req, res) => void handle(req, res)).listen(Number(listen.port), listen.hostname, () =>
  console.log(`listening on ${listen.host}, forwarding to ${backend}`),
);
