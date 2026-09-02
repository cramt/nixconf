#!/usr/bin/env bash
# Scryfall bulk-data helper for the mtg-commander skill.
#
# Everything here exists to keep an agent off the per-card search API. Scryfall
# asks for <10 req/s with a 50-100ms gap between calls; resolving a 100-card
# decklist one request at a time is slow, rude, and gets rate limited. The bulk
# files are the sanctioned way to ask about every card at once.
set -euo pipefail

CACHE="${SCRYFALL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/scryfall}"
# Bulk files rebuild roughly daily; Scryfall explicitly asks callers not to
# re-download them more often than that.
MAX_AGE_SECONDS=$((24 * 60 * 60))
UA="nixconf-mtg-commander-skill/1.0"

mkdir -p "$CACHE"
INDEX="$CACHE/index.json"
TAGS="$CACHE/tags.json"

# Game state for `play` lives outside the cache on purpose: the cache is
# disposable (it's a mirror of Scryfall's bulk files and gets rebuilt daily),
# a game in progress is not.
STATE="${SCRYFALL_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/scryfall/games}"

# Decklist parsing, shared by `check` and `play new`. One copy of this regex,
# not two — it is the fiddliest code in the file and the two callers must agree
# on what a decklist *is*, or a deck could validate at 100 cards and then deal
# a different 100.
PARSE_JQ=$(
  cat <<'JQ'
def keyname: ascii_downcase | gsub("^\\s+|\\s+$"; "");

# Archidekt line: "2x Card Name (set) 123 *F* [Category{flags}]".
# Only quantity and name are mandatory; everything after the name is
# optional decoration. The name is matched lazily so the trailing groups
# win the ambiguity, which is what keeps multi-word names intact.
def parse:
  capture("^\\s*(?<qty>[0-9]+)\\s*[xX]?\\s+(?<name>.*?)"
        + "(?:\\s+\\((?<set>[^)]+)\\)(?:\\s+(?<num>[^\\s\\[]+))?)?"
        + "(?:\\s+\\*[Ff]\\*)?"
        + "(?:\\s+\\[(?<cat>[^\\]]*)\\])?\\s*$")
  | {qty: (.qty | tonumber),
     name: (.name | gsub("^\\s+|\\s+$"; "")),
     category: (.cat // "")};

# A whole decklist file -> [{qty, name, category}]. Requires `jq -Rn` so that
# `inputs` yields raw lines rather than parsed JSON.
def decklist: [ inputs
                | select(test("[^\\s]"))          # blank lines
                | select(test("^\\s*//") | not)   # comment lines
                | parse ];

# In the list but not part of the 100 — a companion is a 101st card (CR
# 903.11). The label varies (Companion / Sideboard / Maybeboard) but a noDeck
# flag is the real signal.
#
# Do NOT widen this to match /sticker/: sticker *sheets* are indeed outside the
# deck, but "Sticker Package" is a perfectly normal category for the real cards
# that apply them (Park Bleater, Ticketomaton, ...). Matching the prefix
# silently dropped five cards from a 100-card list and reported them as
# companions. Categorise sheets as Sideboard, or flag them noDeck.
def outside: (.category | test("^(companion|sideboard|maybe)"; "i"))
             or (.category | test("nodeck"; "i"));

def is_commander: (.category | test("^commander"; "i"));
JQ
)

# Alex's house bans: format-legal cards she doesn't want in a *low bracket*
# deck. Not a playgroup rule — a variance one. Turn-one Sol Ring either wins the
# game on the spot or paints you as the table's archenemy, and neither is a fun
# coinflip. Fine at bracket 4+, where everyone signed up for that.
# Newline-separated; override for other people's decks.
HOUSE_BANS="${MTG_HOUSE_BANS:-Sol Ring}"
# Brackets at or below this are held to the house bans.
HOUSE_BAN_MAX_BRACKET=3

die() {
  printf 'scryfall: %s\n' "$*" >&2
  exit 1
}

fresh() {
  [[ -s $1 ]] || return 1
  (($(($(date +%s) - $(stat -c %Y "$1"))) < MAX_AGE_SECONDS))
}

# --- sync -------------------------------------------------------------------
# Downloads Oracle Cards (one entry per unique card, ~25MB gz — the right file
# for deckbuilding; default_cards is every *printing* and 3x the size) and
# renders a compact index holding only the fields deck work needs.
cmd_sync() {
  if [[ ${1:-} != "--force" ]] && fresh "$INDEX"; then
    printf 'index fresh (%s cards, %s)\n' \
      "$(jq -r '.cards|length' "$INDEX")" "$(jq -r .updated_at "$INDEX")" >&2
    return 0
  fi

  local raw="$CACHE/oracle-cards.jsonl" meta uri updated
  meta=$(curl -sSL --max-time 60 --retry 2 -A "$UA" -H 'Accept: application/json' \
    https://api.scryfall.com/bulk-data/oracle_cards) ||
    die "could not reach the bulk-data endpoint"
  # Scryfall serves these as gzipped JSONL: one card object per line.
  uri=$(jq -er .jsonl_download_uri <<<"$meta") || die "no jsonl_download_uri in metadata"
  updated=$(jq -r .updated_at <<<"$meta")

  echo "downloading oracle cards ($updated)..." >&2
  curl -sSL --max-time 600 -A "$UA" "$uri" | gzip -dc >"$raw.tmp" || die "bulk download failed"
  mv "$raw.tmp" "$raw"

  echo "building index..." >&2
  # `reduce inputs` streams the JSONL line by line, so peak memory is the size
  # of the finished index rather than all 150MB+ of raw card objects.
  jq -n --arg updated "$updated" '
    def keyname: ascii_downcase | gsub("^\\s+|\\s+$"; "");
    # Cards exempt from singleton say so in their own rules text, so read it off
    # the card rather than keeping a hand-maintained list of Rats and Petitioners.
    reduce inputs as $c ({cards: {}, oids: {}};
      {
        name: $c.name,
        ci: ($c.color_identity // []),
        commander_legal: ($c.legalities.commander // "not_legal"),
        game_changer: ($c.game_changer // false),
        type_line: ($c.type_line // ""),
        cmc: ($c.cmc // 0),
        keywords: ($c.keywords // []),
        # Kept in the index so "every card with splice onto Arcane" is a jq pass
        # rather than a hundred API calls. Both faces, for DFCs.
        oracle: (($c.oracle_text // "")
                 + (($c.card_faces // []) | map(.oracle_text // "") | join("\n"))),
        any_number: (($c.oracle_text // "")
                     | test("A deck can have any number of cards named"; "i")),
        usd: ($c.prices.usd // null),
        uri: $c.scryfall_uri
      } as $rec
      | .cards[($c.name | keyname)] = $rec
      # Oracle tags reference cards by oracle_id, so keep the mapping to resolve
      # them back to names without a second pass over the raw file.
      | .oids[$c.oracle_id] = $c.name
      # Split cards and MDFCs are stored as "Front // Back", but decklists (and
      # people) routinely write only the front face. Index both spellings.
      | if ($c.card_faces // [] | length) > 0
        then .cards[($c.card_faces[0].name | keyname)] //= $rec
        else . end
    )
    | {updated_at: $updated} + .
  ' "$raw" >"$INDEX.tmp"
  mv "$INDEX.tmp" "$INDEX"
  printf 'indexed %s names\n' "$(jq -r '.cards|length' "$INDEX")" >&2

  sync_tags "$updated"
}

# Scryfall's community Oracle tags (the `otag:` search prefix) also ship as a
# bulk file, so tag lookups need no API calls either.
sync_tags() {
  local updated=$1 raw="$CACHE/oracle-tags.jsonl" uri
  uri=$(curl -sSL --max-time 60 --retry 2 -A "$UA" -H 'Accept: application/json' \
    https://api.scryfall.com/bulk-data/oracle_tags | jq -er .jsonl_download_uri) ||
    die "could not reach the oracle-tags bulk endpoint"

  echo "downloading oracle tags..." >&2
  curl -sSL --max-time 600 -A "$UA" "$uri" | gzip -dc >"$raw.tmp" || die "tag download failed"
  mv "$raw.tmp" "$raw"

  echo "building tag index..." >&2
  jq -n --slurpfile idx "$INDEX" --arg updated "$updated" '
    ($idx[0].oids) as $oids
    | (reduce inputs as $t ({};
        .[$t.id] = {slug: $t.slug, label: $t.label,
                    description: ($t.description // ""),
                    children: ($t.child_ids // []),
                    own: [$t.taggings[]?.oracle_id]}
      )) as $byid

    # Tags are a hierarchy: `removal` itself has no taggings, its children
    # (removal-exile, removal-bounce, ...) hold them. Scryfall expands children
    # on lookup, so resolve the transitive closure here. Iterating to a fixed
    # point on a uniqued set terminates even if the graph has a cycle.
    | def closure($id):
        [$id]
        | until(
            . == ((. + (map($byid[.].children // []) | add // [])) | unique);
            (. + (map($byid[.].children // []) | add // [])) | unique
          );

    # from_entries rather than `reduce . + {…}`: the latter copies a growing
    # accumulator once per tag, which is quadratic over 4.5k tags.
    { updated_at: $updated,
      tags: ([ $byid | keys_unsorted[] as $id
               | { key: $byid[$id].slug,
                   value: {
                     label: $byid[$id].label,
                     description: $byid[$id].description,
                     cards: ([ closure($id)[] | $byid[.].own[]? | $oids[.] // empty ] | unique)
                   } } ] | from_entries)
    }
  ' "$raw" >"$TAGS.tmp"
  mv "$TAGS.tmp" "$TAGS"
  printf 'indexed %s oracle tags\n' "$(jq -r '.tags|length' "$TAGS")" >&2
}

need_index() {
  fresh "$INDEX" || cmd_sync
  [[ -s $INDEX ]] || die "no index; run: scryfall sync --force"
}

# --- lookups ----------------------------------------------------------------
cmd_card() {
  [[ $# -gt 0 ]] || die "usage: scryfall card <name>"
  need_index
  jq -er --arg n "$*" \
    '.cards[($n|ascii_downcase)] // error("no such card: \($n)")' "$INDEX"
}

# The live Game Changers list. Never hardcode this — it has been revised four
# times since launch (40 cards at launch, then Apr 2025, Oct 2025, Feb 2026).
cmd_gamechangers() {
  need_index
  jq -r '[.cards|to_entries[]|select(.value.game_changer)|.value.name]|unique|.[]' "$INDEX"
}

cmd_path() {
  need_index
  echo "$INDEX"
}

# Discovery: you rarely know a tag's exact slug ("manarock" is really "mana-rock").
cmd_tags() {
  need_index
  jq -r --arg q "${1:-}" '
    [ .tags | to_entries[]
      | select($q == "" or (.key | test($q; "i")) or (.value.description | test($q; "i")))
      | select(.value.cards | length > 0) ]
    | sort_by(-(.value.cards | length))
    | .[] | "\(.key)\t\(.value.cards|length)\t\(.value.description)"
  ' "$TAGS" | column -t -s $'\t'
}

# The local equivalent of Scryfall's `otag:` prefix, with optional colour-identity
# and mana-value filters so results are already deck-relevant.
cmd_otag() {
  [[ $# -gt 0 ]] || die "usage: scryfall otag <slug> [color-identity] [max-cmc]"
  need_index
  local slug=$1 ci=${2:-} maxcmc=${3:-99}
  jq -er --slurpfile idx "$INDEX" \
    --arg slug "$slug" --arg ci "$ci" --argjson maxcmc "$maxcmc" '
    ($idx[0].cards) as $db
    | (.tags[$slug] // error("no such tag: \($slug) — try: scryfall tags <pattern>")) as $t
    | ($ci | ascii_upcase | split("") | map(select(. != ""))) as $want
    | [ $t.cards[]
        | $db[ascii_downcase] // empty
        | select(.cmc <= $maxcmc)
        | select($want == [] or ((.ci - $want) | length == 0))
        | select(.commander_legal == "legal") ]
    | unique_by(.name) | sort_by(.cmc, .name)
    | .[]
    # "C" rather than an empty cell, so colourless rows do not collapse the
    # column layout; strip the ".0" jq puts on whole mana values.
    | "\(.cmc | tostring | sub("\\.0$"; ""))\t\(.name)\t\(if (.ci|length) == 0
        then "C" else (.ci|join("")) end)\t\(.usd // "-")"
  ' "$TAGS" | column -t -s $'\t'
}

# --- check ------------------------------------------------------------------
# Validates an Archidekt-style decklist: size, singleton, commander legality,
# colour identity, and Game Changer count -> minimum legal bracket.
cmd_check() {
  [[ -r ${1:-} ]] || die "usage: scryfall check <decklist-file> [target-bracket]"
  need_index
  # Default to 3: Alex builds 1-3, so the house bans apply unless told otherwise.
  local bracket=${2:-3}
  local report
  report=$(mktemp) && trap 'rm -f "$report"' RETURN

  jq -Rn --slurpfile idx "$INDEX" \
    --arg housebans "$HOUSE_BANS" \
    --argjson bracket "$bracket" \
    --argjson housemax "$HOUSE_BAN_MAX_BRACKET" \
    "$PARSE_JQ"'
    ($idx[0].cards) as $db
    | (if $bracket <= $housemax
       then ($housebans | split("\n") | map(ascii_downcase | gsub("^\\s+|\\s+$"; ""))
             | map(select(length > 0)))
       else [] end) as $house

    | decklist as $lines

    | ($lines | map(. + {rec: $db[(.name | keyname)]})) as $cards
    | ($cards | map(select(.rec == null) | .name))      as $unknown
    | ($cards | map(select(.rec != null)))              as $known
    # Partners, backgrounds and Doctor/companion pairs put two cards in the
    # command zone, and colour identity is their *union* — taking only the first
    # would flag the other partner and its whole colour as illegal.
    | ($known | map(select(is_commander))) as $cmdrs
    | ([ $cmdrs[].rec.ci[]? ] | unique) as $cmdci
    # A companion is a 101st card outside the deck (CR 903.11), so it is counted
    # and colour-checked separately rather than against the 100. `outside` is
    # shared with `play` so both agree on what is not part of the deck proper.
    | ($known | map(select(outside)))       as $comps
    | ($known | map(select(outside | not))) as $deck

    | {
        total: ([ $deck[] | .qty ] | add // 0),
        target_bracket: $bracket,
        commanders: [ $cmdrs[].rec.name ],
        commander_identity: $cmdci,
        companion: [ $comps[].rec.name ],
        # A companion sits outside the 100 but must still be inside the
        # combined commander colour identity (CR 903.11).
        companion_identity_violations: [ $comps[]
          | select((.rec.ci - $cmdci) | length > 0)
          | {name: .rec.name, identity: .rec.ci} ],
        unknown: $unknown,
        illegal: [ $known[]
          | select(.rec.commander_legal != "legal")
          | {name: .rec.name, status: .rec.commander_legal} ],
        # Colour identity is the card-level field, never the mana cost: it also
        # covers reminder text, activated-ability costs and the back of a MDFC.
        # Array subtraction leaves whatever the commanders cannot support.
        color_identity_violations: [ $deck[]
          | select((.rec.ci - $cmdci) | length > 0)
          | {name: .rec.name, identity: .rec.ci} ],
        singleton_violations: [ $deck[]
          | select(.qty > 1)
          | select(((.rec.type_line | test("Basic Land")) or .rec.any_number) | not)
          | {name: .rec.name, qty: .qty} ],
        game_changers: ([ $deck[] | select(.rec.game_changer) | .rec.name ] | sort),
        house_ban_violations: [ $deck[]
          | select(.rec.name | ascii_downcase | IN($house[]))
          | .rec.name ],
        # Computed here because an agent without `bc` on PATH will otherwise
        # hand-roll this and get an empty answer.
        usd_total: ([ $deck[] | (.rec.usd // "0" | tonumber) * .qty ] | add // 0
                    | . * 100 | round / 100),
        priciest: ([ $deck[] | select(.rec.usd != null)
                     | {name: .rec.name, usd: (.rec.usd | tonumber)} ]
                   | sort_by(-.usd) | .[0:8])
      }
    | .game_changer_count = (.game_changers | length)
    # Game Changers only ever set a *floor*. Mass land denial, early two-card
    # combos and chained extra turns also push a deck up, and none of those are
    # detectable from card data — a human still has to read the deck.
    | .min_bracket_from_game_changers =
        (if .game_changer_count == 0 then 1
         elif .game_changer_count <= 3 then 3
         else 4 end)
    | .errors = ((.unknown | length) + (.illegal | length)
                 + (.color_identity_violations | length)
                 + (.singleton_violations | length)
                 + (.companion_identity_violations | length)
                 + (if .total == 100 then 0 else 1 end))
    | .legal = (.errors == 0)
    | .ok = (.legal and (.house_ban_violations | length) == 0)
    # Human-readable one-liner, duplicated to stderr by the caller. The script
    # cannot check mass land denial, cheap combos, chained extra turns, or the
    # deckbuilding restriction a companion imposes — say so rather than let a
    # green verdict imply otherwise.
    | .verdict = (if .ok then "PASS" else
        "FAIL: " + ([
          (if .total != 100 then "\(.total) cards, expected 100" else empty end),
          (if (.unknown|length) > 0 then "\(.unknown|length) unknown card(s): \(.unknown|join(", "))" else empty end),
          (if (.illegal|length) > 0 then "\(.illegal|length) not commander-legal" else empty end),
          (if (.color_identity_violations|length) > 0 then "\(.color_identity_violations|length) outside colour identity \(.commander_identity|join(""))" else empty end),
          (if (.singleton_violations|length) > 0 then "\(.singleton_violations|length) singleton violation(s)" else empty end),
          (if (.companion_identity_violations|length) > 0 then "companion outside colour identity" else empty end),
          (if (.house_ban_violations|length) > 0 then "house ban: \(.house_ban_violations|join(", "))" else empty end)
        ] | join("; ")) end)
    | .unchecked = "mass land denial, early two-card combos, chained extra turns, companion deckbuilding restriction"
  ' "$1" >"$report"

  cat "$report"
  # The verdict also goes to stderr, and the exit code reflects it. A caller that
  # pipes stdout through `jq '{some,fields}'` can drop the failure from the JSON
  # — that has happened — but stderr still lands in front of whoever is reading.
  jq -r '.verdict' "$report" >&2
  jq -e '.ok' "$report" >/dev/null
}

# --- play -------------------------------------------------------------------
# A shuffled deck with honest zone bookkeeping. Deliberately NOT a rules
# engine: it owns the randomness and where every card is, and the caller makes
# every decision. There is no mana pool, stack, priority or combat here on
# purpose — the tool only tracks what it can be authoritative about, and an
# agent that has to state its own plays out loud cannot quietly fudge them.
#
# Shuffling is `shuf`, never a hand-rolled PRNG. Two prototypes were rejected
# for producing confident wrong numbers: an LCG in jq dealt 82% of opening
# hands at exactly 1 land (correct: 16.4%), and an awk srand() keystream fed to
# --random-source biased the mean lands-in-seven to 2.3195 against a true
# 2.5457 — eight standard errors off.
#
# The acceptance test for any change to the shuffle is the hypergeometric
# distribution for the deck. For 36 lands in 99 cards, n=7: mean 2.5457,
# SD 1.2331, so 2000 deals should land within ~3 SE (0.0276) of the mean,
# i.e. 2.46-2.63. Both `shuf` and the openssl keystream cleared this.
GAME=default

game_file() { printf '%s/%s.json' "$STATE" "$GAME"; }

need_game() {
  [[ -s $(game_file) ]] ||
    die "no game '$GAME'; start one with: scryfall play new <decklist>"
}

# `shuf` seeded from urandom by default. With a seed, route through the AES-CTR
# keystream that the coreutils manual documents for reproducible `shuf`/`sort
# -R`: it is uniform by construction, which is exactly what the rejected
# prototypes above were not.
shuffle_lines() {
  if [[ -n ${1:-} ]]; then
    # Without this guard a missing openssl yields an empty keystream and `shuf`
    # dies with a bare "end of file" naming a /dev/fd path, which tells you
    # nothing about the actual cause.
    command -v openssl >/dev/null ||
      die "seeded shuffles need openssl on PATH; drop --seed for an unseeded deal"
    shuf --random-source=<(openssl enc -aes-256-ctr -pass "pass:$1" -nosalt \
      </dev/zero 2>/dev/null)
  else
    shuf
  fi
}

# Play-time jq helpers. `locate` refuses an ambiguous match rather than
# guessing: silently moving the wrong copy of Plains is precisely the
# bookkeeping error this tool exists to make impossible.
PLAY_JQ=$(
  cat <<'JQ'
def zones_order: ["library","hand","battlefield","graveyard","exile","command"];

# Search order when --from is not given. The library is deliberately absent:
# it holds copies of most cards, so including it made almost every move
# ambiguous ("move Plains battlefield" collided with the 16 Plains still in the
# library). Cards leave the library by drawing, or by `top`/`bottom` after a
# peek — reach for it explicitly with --from library.
def search_order: ["hand","battlefield","command","graveyard","exile"];

# First zone in priority order that holds a match wins, and duplicates within
# one zone are interchangeable so the first will do. `state` prints the result
# straight after every move, so the resolution is always visible rather than
# silent.
def locate($q; $from):
  [ (if $from == "" then search_order[] else $from end) as $z
    | (.zones[$z] // error("no such zone: \($z)")) | to_entries[]
    | select(.value.id == $q or (.value.name | ascii_downcase) == ($q | ascii_downcase))
    | {zone: $z, idx: .key} ]
  | if length == 0
      then error("not found: \($q)"
                 + (if $from == "" then " in hand/battlefield/command/graveyard/exile"
                                        + " — pass --from library to reach the library"
                    else " in \($from)" end))
    else (.[0].zone) as $z | map(select(.zone == $z)) | .[0] end;

# Battlefield cards carry tapped state and counters; everywhere else they are
# just {id, name}. Strip on the way out so a card does not remember that it
# was tapped three zones ago, and seed the fields on the way in.
def entering($to; $c; $tapped):
  if $to == "battlefield"
  then {id: $c.id, name: $c.name, tapped: $tapped, counters: ($c.counters // {})}
  else {id: $c.id, name: $c.name} end;

def move_one($q; $from; $to; $tapped):
  (if (.zones | has($to)) then . else error("no such zone: \($to)") end)
  | locate($q; $from) as $at
  | .zones[$at.zone][$at.idx] as $c
  | .zones[$at.zone] |= del(.[$at.idx])
  | .zones[$to] += [entering($to; $c; $tapped)];

def draw_n($n):
  if $n > (.zones.library | length)
  then error("cannot draw \($n): library has \(.zones.library | length)")
  else .zones.hand += .zones.library[:$n]
       | .zones.library |= .[$n:] end;
JQ
)

# Read-modify-write on the state file. Every mutating subcommand goes through
# here so the write is atomic (temp file then mv) and the log entry cannot be
# forgotten. A half-written state would lose or duplicate cards, which is the
# one failure mode that would make the whole tool worthless.
# The `filter` arguments callers pass in are jq programs, so their `$name`
# references are jq bindings supplied via --arg, not shell expansions.
# shellcheck disable=SC2016
state_edit() {
  local msg=$1 filter=$2
  shift 2
  local f
  f=$(game_file)
  jq --arg _log "$msg" "$@" "$PLAY_JQ$filter"' | .log += [$_log]' "$f" >"$f.tmp" ||
    die "refused: $msg"
  mv "$f.tmp" "$f"
  printf '%s\n' "$msg" >&2
}

play_new() {
  [[ -r ${1:-} ]] || die "usage: scryfall play new <decklist> [--seed S] [--name G]"
  need_index
  local deck=$1 seed=
  shift
  while [[ $# -gt 0 ]]; do
    case $1 in
    --seed)
      [[ $# -ge 2 ]] || die "--seed needs a value"
      seed=$2
      shift 2
      ;;
    *) die "play new: unknown option: $1" ;;
    esac
  done

  mkdir -p "$STATE"
  local f
  f=$(game_file)

  # Quantities are expanded into individual instances up front: the list says
  # "18x Plains", and a library holding one Plains deals nothing like the real
  # deck. Ids are stable so `move` can name a specific copy.
  jq -Rn --slurpfile idx "$INDEX" \
    --arg deck "$deck" --arg seed "$seed" --arg game "$GAME" \
    "$PARSE_JQ"'
    ($idx[0].cards) as $db
    | decklist as $lines
    | ([ $lines[] | select((.name | keyname) | in($db) | not) | .name ]) as $unknown
    | if ($unknown | length) > 0
      then error("unknown card(s): \($unknown | join(", ")) — run `scryfall check` first")
      else . end
    | [ $lines[] | select(outside | not) | . as $l
        | range(1; $l.qty + 1)
        | {id: (($l.name | keyname | gsub("[^a-z0-9]+"; "-")) + "#" + tostring),
           name: $l.name,
           cmdr: ($l | is_commander)} ] as $all
    | {game: $game, deck: $deck, seed: $seed, turn: 0, mulligans: 0, owed: 0,
       zones: {
         library:     [$all[] | select(.cmdr | not) | {id, name}],
         hand: [], battlefield: [], graveyard: [], exile: [],
         command:     [$all[] | select(.cmdr) | {id, name}]
       },
       log: []}
  ' "$deck" >"$f.tmp" || die "could not build a game from $deck"
  mv "$f.tmp" "$f"

  play_shuffle "$seed"
  state_edit "opening hand" 'draw_n(7)'
  play_state
}

# Reorders the library by shuffling its ids as lines, so the randomness comes
# from `shuf` rather than from anything written here.
play_shuffle() {
  local f order
  f=$(game_file)
  order=$(jq -r '.zones.library[].id' "$f" | shuffle_lines "${1:-}" | jq -Rn '[inputs]')
  jq --argjson order "$order" '
    .zones.library = ((.zones.library | INDEX(.id)) as $by | [$order[] | $by[.]])
  ' "$f" >"$f.tmp" || die "shuffle failed"
  mv "$f.tmp" "$f"
}

# London mulligan: a fresh seven every time, then N cards to the bottom. `owed`
# records the debt so `bottom` can pay it down rather than trusting memory.
play_mull() {
  need_game
  local n
  n=$(($(jq -r '.mulligans' "$(game_file)") + 1))
  state_edit "mulligan to $((7 - n))" \
    '.zones.library += .zones.hand | .zones.hand = [] | .mulligans += 1'
  # Derive a fresh seed per mulligan so the second seven is not the first one
  # again — but only when the game was seeded at all. Deriving unconditionally
  # would turn an unseeded game into a seeded one from "m1" onward.
  play_shuffle "$(jq -r 'if .seed == "" then "" else .seed + "m" + (.mulligans | tostring) end' \
    "$(game_file)")"
  state_edit "new seven, $n owed to the bottom" 'draw_n(7) | .owed = .mulligans'
  play_state
}

# One jq pass over the index, and the padding is computed per section inside
# jq. Two things this avoids: slurping a 25MB index once per zone (this runs
# after every single mutation, so it has to be cheap), and piping everything
# through one `column` pass, which lets the longest type line in the graveyard
# set the hand column widths and silently eats the blank lines between
# sections.
play_state() {
  need_game
  need_index
  jq -r --slurpfile idx "$INDEX" "$PLAY_JQ"'
    ($idx[0].cards) as $db
    | . as $s
    | def typ($n): ($db[$n | ascii_downcase].type_line // "?");
      def mv($n): ($db[$n | ascii_downcase].cmc // 0 | tostring | sub("\\.0$"; ""));
      # jq multiplies a string by 0 to null rather than "", so guard the width.
      def pad($w): . + (($w - length) as $k
                        | if $k > 0 then " " * $k else "" end);
      # rows are [col, col, ...]; widths are measured within one section only
      def table($rows):
        ($rows | map(map(length)) | transpose | map(max)) as $w
        | $rows[] | [range(0; length) as $i | .[$i] | pad($w[$i])]
                    | join("  ") | sub(" +$"; "");

      "game \(.game)   turn \(.turn)   seed \(if .seed == "" then "random" else .seed end)"
      + "   mulls \(.mulligans)\(if .owed > 0 then "   OWED \(.owed) to bottom" else "" end)",
      ([zones_order[] | "\(.) \($s.zones[.] | length)"] | join("   ")),

      (zones_order[] as $z
       | $s.zones[$z] as $cards
       | if ($cards | length) == 0 or $z == "library" then empty
         else
           "",
           "\($z | ascii_upcase) (\($cards | length))",
           table(
             if $z == "battlefield"
             then [$cards[] | ["  " + .name,
                               (if .tapped then "TAPPED" else "untapped" end),
                               typ(.name),
                               ((.counters // {}) | to_entries
                                | map("\(.key)=\(.value)") | join(" "))]]
             # Hand and the rest group by name: five separate Plains lines is
             # noise, "5x Plains" is the thing you actually reason about.
             else [$cards | group_by(.name) | sort_by(-length, .[0].name)[]
                   | ["  " + (if length > 1 then "\(length)x " else "" end) + .[0].name,
                      "mv " + mv(.[0].name),
                      typ(.[0].name)]]
             end)
         end)
  ' "$(game_file)" >&2
}

play_peek() {
  need_game
  need_index
  local n=${1:-1}
  jq -r --slurpfile idx "$INDEX" --argjson n "$n" '
    ($idx[0].cards) as $db
    | "top \($n) of library (still there — use `play top`/`play bottom` after a scry):",
      (.zones.library[:$n][]
       | "  \(.id)\t\(.name)\t\($db[.name | ascii_downcase].type_line // "?")")
  ' "$(game_file)" | column -t -s $'\t' >&2
}

# As in state_edit: the single-quoted strings below are jq programs handed to
# state_edit, so their `$name` references are jq bindings, not shell ones.
# shellcheck disable=SC2016
cmd_play() {
  # --name is valid on every subcommand, so strip it before dispatch instead of
  # repeating the flag in a dozen little parsers.
  local args=()
  while [[ $# -gt 0 ]]; do
    case $1 in
    --name)
      [[ $# -ge 2 ]] || die "--name needs a value"
      GAME=$2
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  set -- ${args[@]+"${args[@]}"}

  local sub=${1:-state}
  [[ $# -gt 0 ]] && shift

  case $sub in
  new) play_new "$@" ;;
  state) play_state ;;
  peek) play_peek "$@" ;;
  mull | mulligan) play_mull ;;
  log)
    need_game
    jq -r '.log[]' "$(game_file)"
    ;;
  draw)
    need_game
    state_edit "draw ${1:-1}" 'draw_n($n)' --argjson n "${1:-1}"
    play_state
    ;;
  turn)
    need_game
    local nodraw=${1:-}
    state_edit "turn" '.turn += 1 | .zones.battlefield |= map(.tapped = false)'
    [[ $nodraw == --no-draw ]] || state_edit "draw for turn" 'draw_n(1)'
    play_state
    ;;
  move)
    need_game
    [[ $# -ge 2 ]] ||
      die "usage: scryfall play move <card> <to-zone> [--from <zone>] [--tapped]"
    local card=$1 to=$2 from='' tapped=false
    shift 2
    while [[ $# -gt 0 ]]; do
      case $1 in
      --from)
        [[ $# -ge 2 ]] || die "--from needs a zone"
        from=$2
        shift 2
        ;;
      --tapped)
        tapped=true
        shift
        ;;
      *) die "play move: unknown option: $1" ;;
      esac
    done
    state_edit "move $card -> $to$([[ $tapped == true ]] && echo ' (tapped)')" \
      'move_one($c; $f; $t; $tap)' \
      --arg c "$card" --arg f "$from" --arg t "$to" --argjson tap "$tapped"
    play_state
    ;;
  tap | untap)
    need_game
    [[ $# -ge 1 ]] || die "usage: scryfall play $sub <card>"
    local want=true
    [[ $sub == untap ]] && want=false
    state_edit "$sub $1" \
      'locate($c; "battlefield") as $at | .zones.battlefield[$at.idx].tapped = $v' \
      --arg c "$1" --argjson v "$want"
    ;;
  counter)
    need_game
    [[ $# -ge 3 ]] ||
      die "usage: scryfall play counter <card> <kind> <delta>   e.g. counter 'City of Shadows' storage +1"
    state_edit "counter $1 $2 $3" '
      locate($c; "battlefield") as $at
      | .zones.battlefield[$at.idx].counters[$k] =
          (((.zones.battlefield[$at.idx].counters[$k] // 0) + $d) | if . < 0 then 0 else . end)
      | if .zones.battlefield[$at.idx].counters[$k] == 0
        then .zones.battlefield[$at.idx].counters |= del(.[$k]) else . end' \
      --arg c "$1" --arg k "$2" --argjson d "$3"
    play_state
    ;;
  top | bottom)
    need_game
    [[ $# -ge 1 ]] ||
      die "usage: scryfall play $sub <card> [--from <zone>]   (--from library after a scry)"
    local tcard=$1 tfrom=''
    shift
    while [[ $# -gt 0 ]]; do
      case $1 in
      --from)
        [[ $# -ge 2 ]] || die "--from needs a zone"
        tfrom=$2
        shift 2
        ;;
      *) die "play $sub: unknown option: $1" ;;
      esac
    done
    local pos='[$e] + .zones.library'
    [[ $sub == bottom ]] && pos='.zones.library + [$e]'
    # Reordering after a scry means the card is already in the library, which
    # the default search order excludes — hence --from library.
    state_edit "$sub of library: $tcard" "
      locate(\$c; \$f) as \$at
      | .zones[\$at.zone][\$at.idx] as \$e
      | .zones[\$at.zone] |= del(.[\$at.idx])
      | .zones.library = ($pos)
      | if \$at.zone == \"hand\" and .owed > 0 then .owed -= 1 else . end" \
      --arg c "$tcard" --arg f "$tfrom"
    play_state
    ;;
  end)
    need_game
    rm -f "$(game_file)"
    printf 'game %s deleted\n' "$GAME" >&2
    ;;
  *) die "play: unknown subcommand '$sub' (new|state|draw|mull|peek|top|bottom|move|tap|untap|turn|counter|log|end)" ;;
  esac
}

case "${1:-}" in
sync) shift; cmd_sync "$@" ;;
card) shift; cmd_card "$@" ;;
gamechangers | gc) shift; cmd_gamechangers "$@" ;;
check) shift; cmd_check "$@" ;;
path) shift; cmd_path "$@" ;;
tags) shift; cmd_tags "$@" ;;
otag) shift; cmd_otag "$@" ;;
play) shift; cmd_play "$@" ;;
*)
  cat >&2 <<'USAGE'
usage: scryfall <command>

  sync [--force]   refresh the cached bulk indexes (auto, max 1/day)
  card <name>      one card's deck-relevant fields
  gamechangers     the live Game Changers list
  check <file> [b] validate an Archidekt-style decklist (JSON report)
  tags [pattern]   find Oracle tag slugs, biggest first
  otag <slug> [ci] [max-cmc]
                   cards carrying an Oracle tag, optionally filtered to a colour
                   identity and mana value, e.g. `otag mana-rock GUR 2`
  path             path to the index, for your own jq queries
  play <subcommand>
                   deal and play out a real shuffled deck (see below)

`play` is a shuffled deck plus zone bookkeeping — not a rules engine. It owns
the randomness and where every card is; you make every decision.

  play new <file> [--seed S]  shuffle, put the commander in the command zone,
                              draw seven
  play state                  every zone, with type line and mana value
  play draw [n]               draw n (default 1)
  play mull                   London mulligan: fresh seven, N owed to the bottom
  play peek [n]               look at the top n without moving them (scry)
  play top|bottom <card> [--from <zone>]
                              put a card on top of / under the library;
                              after a scry the card is already there, so
                              reach for it with --from library
  play move <card> <zone> [--from <zone>] [--tapped]
  play tap|untap <card>
  play turn [--no-draw]       untap everything, next turn, draw
  play counter <card> <kind> <delta>
  play log | play end
  --name <G>                  run several games at once (default: "default")

Zones are library, hand, battlefield, graveyard, exile, command. Every
subcommand accepts --name. A worked turn:

  scryfall play new deck.txt --seed 42
  scryfall play move Plains battlefield
  scryfall play tap Plains
  scryfall play counter "City of Shadows" storage +1
  scryfall play turn

The index is {updated_at, cards: {"lowercased name": {...}}}, so arbitrary
questions are one jq away — no API calls, no rate limit:

  jq -r '[.cards|to_entries[]|select(.value.ci==["G"] and .value.cmc<=2)
          |.value.name]|sort|.[]' "$(scryfall path)"
USAGE
  exit 64
  ;;
esac
