#!/usr/bin/env bash
# Transcript corpus of Commander deckbuilding creators, for the mtg skills.
#
# The skills distil these into cited principles, but a brew around a specific
# commander or card wants the raw material too: "did any of them build this?"
# is a grep away once the transcripts are local. They live in the cache, not in
# git, because they're the creators' words, not ours; only the distilled,
# attributed lessons get committed.
set -euo pipefail

CACHE="${MTG_LORE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mtg-lore}"

# handle [<TAB> title filter (ERE, case-insensitive)]; no filter = every upload.
# Magic Mirror (Trinket Mage, 3/3 Elk, Salubrious Snail) is posted on The
# Trinket Mage's channel. VeggieWagon's own channel is skits; his deckbuilding
# is on Decked Out EDH, which is otherwise mostly gameplay, so that keeps only
# the Good Time Boys podcast (with Maldhound) and its card-list videos.
SOURCES="thetrinketmage
33elk
salubrioussnail
Maldhound
DeckedOutEDH	good ?time ?boys|^the best |^top [0-9]"

die() {
  echo "mtg-lore: $*" >&2
  exit 1
}

ytdlp() {
  # Paced well under anything YouTube throttles: a full first sync is ~1000
  # videos, and a 429 mid-run costs more than the sleeps.
  yt-dlp --quiet --no-warnings --sleep-requests 1 "$@"
}

# YouTube's auto-captions roll: each cue repeats the previous line and adds a
# new one carrying <c> word-timing tags. Keep only the new lines (or, for
# hand-made captions with no tags, every line), then fold them into ~30s
# paragraphs so a grep hit carries enough context and a timestamp to link to.
vtt_to_text() {
  local tagged=0
  grep -q '<c>' "$1" && tagged=1
  gawk -v tagged="$tagged" '
    function secs(t,  a) { split(t, a, /[:.]/); return a[1]*3600 + a[2]*60 + a[3] }
    function flush() {
      if (buf != "") printf "[%d:%02d:%02d] %s\n", int(start/3600), int(start%3600/60), start%60, buf
      buf = ""
    }
    / --> / { t = secs($1); next }
    /^(WEBVTT|Kind:|Language:)/ || /^[[:space:]]*$/ { next }
    {
      if (tagged && $0 !~ /<c>/) next
      line = $0
      gsub(/<[^>]*>/, "", line)
      gsub(/&nbsp;/, " ", line); gsub(/&amp;/, "\\&", line); gsub(/&gt;/, ">", line); gsub(/&lt;/, "<", line)
      if (line == prev) next
      prev = line
      if (buf == "") start = t
      else if (t - start >= 30) { flush(); start = t }
      buf = (buf == "" ? line : buf " " line)
    }
    END { flush() }
  ' "$1"
}

cmd_sync() {
  local only=("$@") handle filter
  while IFS=$'\t' read -r handle filter; do
    if [[ ${#only[@]} -gt 0 ]] && [[ ! " ${only[*]} " == *" $handle "* ]]; then continue; fi
    local dir="$CACHE/$handle" new=0 skipped=0
    mkdir -p "$dir"
    echo "== $handle" >&2
    local listing
    listing=$(ytdlp --flat-playlist --print $'%(id)s\t%(title)s' \
      "https://www.youtube.com/@$handle/videos") || die "could not list @$handle"
    while IFS=$'\t' read -r id title; do
      [[ -n $id ]] || continue
      if [[ -n $filter ]] && ! grep -qiE "$filter" <<<"$title"; then continue; fi
      # .none marks a video with no English captions, so it isn't retried forever.
      if [[ -e $dir/$id.txt || -e $dir/$id.none ]]; then continue; fi
      local tmp date
      tmp=$(mktemp -d)
      if ! date=$(ytdlp --skip-download --no-simulate --write-subs --write-auto-subs \
        --sub-langs en --sub-format vtt -o "$tmp/%(id)s" --print '%(upload_date)s' \
        "https://www.youtube.com/watch?v=$id" </dev/null); then
        echo "  failed: $id $title (will retry next sync)" >&2
        rm -rf "$tmp"
        continue
      fi
      local vtt
      vtt=$(find "$tmp" -name '*.vtt' | head -1)
      if [[ -z $vtt ]]; then
        touch "$dir/$id.none"
        skipped=$((skipped + 1))
      else
        {
          printf '# %s\n# https://www.youtube.com/watch?v=%s\n# @%s %s\n' "$title" "$id" "$handle" "$date"
          vtt_to_text "$vtt"
        } >"$dir/$id.txt.tmp"
        mv "$dir/$id.txt.tmp" "$dir/$id.txt"
        new=$((new + 1))
        echo "  + $date $title" >&2
      fi
      rm -rf "$tmp"
    done <<<"$listing"
    echo "  $new new, $skipped without captions" >&2
  done <<<"$SOURCES"
}

# handle <TAB> date <TAB> id <TAB> title, newest first.
cmd_list() {
  local pat=${1:-}
  shopt -s nullglob
  local f
  for f in "$CACHE"/*/*.txt; do
    gawk -v id="$(basename "$f" .txt)" '
      NR == 1 { title = substr($0, 3) }
      NR == 3 { split($0, a, " "); printf "%s\t%s\t%s\t%s\n", substr(a[2], 2), a[3], id, title; exit }
    ' "$f"
  done | { if [[ -n $pat ]]; then grep -iE -- "$pat" || true; else cat; fi; } | sort -t$'\t' -k2,2r
}

# Every ~30s paragraph matching the pattern, with a link straight to that moment.
cmd_search() {
  [[ $# -ge 1 ]] || die "usage: mtg-lore search <regex> [handle]"
  local pat=$1
  shopt -s nullglob
  local files
  if [[ -n ${2:-} ]]; then files=("$CACHE/$2"/*.txt); else files=("$CACHE"/*/*.txt); fi
  [[ ${#files[@]} -gt 0 ]] || die "no transcripts under $CACHE — run \`mtg-lore sync\`"
  gawk -v pat="$pat" '
    BEGIN { IGNORECASE = 1 }
    FNR == 1 { title = substr($0, 3) }
    FNR == 2 { url = substr($0, 3) }
    FNR == 3 { who = $2; date = $3 }
    FNR > 3 && $0 ~ pat {
      match($0, /^\[([0-9]+):([0-9]+):([0-9]+)\]/, m)
      printf "%s %s | %s\n  %s&t=%ds\n  %s\n\n", who, date, title, url, m[1]*3600 + m[2]*60 + m[3], $0
    }
  ' "${files[@]}"
}

cmd_show() {
  [[ $# -eq 1 ]] || die "usage: mtg-lore show <video-id>"
  local f
  f=$(find "$CACHE" -name "$1.txt" | head -1)
  [[ -n $f ]] || die "no transcript for $1"
  cat "$f"
}

sub=${1:-}
shift || true
case $sub in
sync) cmd_sync "$@" ;;
list) cmd_list "$@" ;;
search) cmd_search "$@" ;;
show) cmd_show "$@" ;;
path) echo "$CACHE" ;;
sources) echo "$SOURCES" ;;
*)
  cat >&2 <<'EOF'
usage: mtg-lore <command>
  sync [handle...]          fetch new transcripts (incremental; first run is ~1h)
  list [regex]              videos as handle/date/id/title, newest first, title-filtered
  search <regex> [handle]   matching ~30s paragraphs with timestamped links
  show <video-id>           a whole transcript
  path                      the corpus directory
  sources                   channels synced, and their title filters
EOF
  exit 1
  ;;
esac
