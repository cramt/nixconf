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
    --argjson housemax "$HOUSE_BAN_MAX_BRACKET" '
    ($idx[0].cards) as $db
    | (if $bracket <= $housemax
       then ($housebans | split("\n") | map(ascii_downcase | gsub("^\\s+|\\s+$"; ""))
             | map(select(length > 0)))
       else [] end) as $house

    | def keyname: ascii_downcase | gsub("^\\s+|\\s+$"; "");

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

    [ inputs
      | select(test("[^\\s]"))          # blank lines
      | select(test("^\\s*//") | not)   # comment lines
      | parse ] as $lines

    | ($lines | map(. + {rec: $db[(.name | keyname)]})) as $cards
    | ($cards | map(select(.rec == null) | .name))      as $unknown
    | ($cards | map(select(.rec != null)))              as $known
    # Partners, backgrounds and Doctor/companion pairs put two cards in the
    # command zone, and colour identity is their *union* — taking only the first
    # would flag the other partner and its whole colour as illegal.
    | ($known | map(select(.category | test("^commander"; "i")))) as $cmdrs
    | ([ $cmdrs[].rec.ci[]? ] | unique) as $cmdci
    # A companion is a 101st card outside the deck (CR 903.11), so it is counted
    # and colour-checked separately rather than against the 100. Match on any of
    # the conventions used for "not in the deck proper" — the label varies
    # (Companion / Sideboard / Maybeboard) but the noDeck flag is the real signal.
    | def outside: (.category | test("^(companion|sideboard|maybe)"; "i"))
                   or (.category | test("nodeck"; "i"));
      ($known | map(select(outside)))       as $comps
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

case "${1:-}" in
sync) shift; cmd_sync "$@" ;;
card) shift; cmd_card "$@" ;;
gamechangers | gc) shift; cmd_gamechangers "$@" ;;
check) shift; cmd_check "$@" ;;
path) shift; cmd_path "$@" ;;
tags) shift; cmd_tags "$@" ;;
otag) shift; cmd_otag "$@" ;;
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

The index is {updated_at, cards: {"lowercased name": {...}}}, so arbitrary
questions are one jq away — no API calls, no rate limit:

  jq -r '[.cards|to_entries[]|select(.value.ci==["G"] and .value.cmc<=2)
          |.value.name]|sort|.[]' "$(scryfall path)"
USAGE
  exit 64
  ;;
esac
