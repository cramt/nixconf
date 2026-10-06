---
name: mtg
description: 'Use for any Magic: The Gathering question — card lookups ("what does X do", "is there a card that…"), rules and interactions ("does this combo work", "how does layers/replacement/state-based actions resolve here"), mining mechanics ("every card with Splice"), and building, playtesting or measuring a deck in any format. Covers the `scryfall` bulk-data CLI, Oracle tags, the Comprehensive Rules, `scryfall play`, `gauntlet` draw-probability tests and where decks live. For Commander/EDH work also load mtg-commander, which builds on this.'
---

# Magic: The Gathering

## The one non-negotiable rule: Scryfall is the source of truth

**Never answer a card question from memory.** Two independent reasons, both sufficient:

1. Magic prints thousands of cards a year. Anything past your cutoff simply isn't in you.
2. Even for cards you "know", you are a model, not a database. Oracle text gets errata'd,
   cards get banned and unbanned, and lists like Commander's Game Changers get revised.
   Confident recall is not the same as correct recall.

Concretely, you do not know and must look up: whether a card exists, its current oracle
text, mana cost, colour identity, legality, or price.

## Use bulk data, not the search API

Scryfall asks callers to stay under ~10 requests/sec with a 50–100ms gap. Resolving a
decklist one `/cards/named` call at a time is slow, rude, and gets rate limited. Scryfall's
answer to this is the bulk data files, and there's a helper wrapping them:

```bash
scryfall sync                     # refresh cached indexes (automatic, at most once/day)
scryfall card "Rhystic Study"     # one card's deck-relevant fields
scryfall tags [pattern]           # find Oracle tag slugs
scryfall otag <slug> [ci] [cmc]   # cards carrying an Oracle tag
scryfall lands <ci> [regex]       # the land pool for an identity, MDFCs first
scryfall path                     # path to the index, for arbitrary jq
scryfall play new <file>          # deal a real shuffled deck and play it out
scryfall gamechangers             # Commander only, see mtg-commander
scryfall check <file> [bracket]   # Commander only, see mtg-commander
```

A second binary, `gauntlet`, answers how often a deck actually has its pieces by turn N.
See [Test whether it functions](#test-whether-it-functions-gauntlet). It also owns
decklist parsing outright: `check` and `play` shell out to it, so all three agree on what a
decklist is by construction.

The first `sync` takes about a minute and then serves everything from disk. Each card record
is `{name, ci, commander_legal, game_changer, type_line, layout, cmc, mana_cost, keywords,
oracle, any_number, usd, uri}`, keyed by lowercased name under `.cards`, so open-ended
questions are a jq away with **zero** API calls:

```bash
# every 1-mana green creature that could plausibly be a mana dork
jq -r '[.cards|to_entries[]|select(.value.ci==["G"] and .value.cmc==1
        and (.value.type_line|test("Creature")))|.value.name]|sort|.[]' "$(scryfall path)"
```

The index carries full `oracle` text (both faces) and `keywords`, which makes mining an
obscure mechanic a local grep:

```bash
P="$(scryfall path)"
# every card with Splice onto Arcane (27 of them)
jq -r '[.cards|to_entries[]|select(.value.oracle|test("Splice onto Arcane";"i"))
        |.value.name]|unique|.[]' "$P"
# every Gate
jq -r '[.cards|to_entries[]|select(.value.type_line|test("Gate"))|.value.name]|unique|.[]' "$P"
# keyword-driven build-arounds
jq -r '[.cards|to_entries[]|select(.value.keywords|index("Forecast"))|.value.name]|unique|.[]' "$P"
```

### The second index: gauntlet's, for formats, printings and stats

`gauntlet sync` downloads the same Scryfall bulk data and builds its own index at
`~/.cache/scryfall/index.jsonl`. It carries what the `scryfall` index doesn't: legality in
**every format**, printings, `produces` (the colours a card's mana abilities make), `rarity`,
`set`, and per-face `power`/`toughness`/`loyalty`. Reach for it for anything outside
Commander, for pauper/rarity questions, and for "which card is `cmr/472`".

The format is not plain JSON lines: line 1 is a header (`updated_at`, counts), then
`<lowercased name>\t<card json>` per card, then `printing:<set>/<num>\t"<name>"` per printing.
Strip it down before jq:

```bash
G=~/.cache/scryfall/index.jsonl     # run `gauntlet sync` first if it's missing or stale
cards() { awk -F'\t' 'NR>1 && $1 !~ /^printing:/ {print $2}' "$G"; }

# .legalities is one letter per format (l legal, n not legal, b banned, r restricted), in order:
# standard future historic timeless gladiator pioneer modern legacy pauper vintage penny
# commander oathbreaker standardbrawl brawl competitivebrawl alchemy paupercommander duel
# oldschool premodern predh tlr  → modern is [6:7], legacy [7:8], pauper [8:9], commander [11:12]
cards | jq -r 'select(.legalities[8:9]=="l" and (.oracle|test("Splice onto";"i")))|.name'
cards | jq -r 'select(.legalities[6:7]=="b")|.name'          # Modern banlist
grep -P '^printing:cmr/472\t' "$G"                           # → "Sol Ring"
```

A full pass is about half a second. Its `tags` array holds **direct** Oracle taggings only,
with no parent expansion: `index("removal")` matches nothing, where `scryfall otag removal`
finds ~6100. Use `otag` for broad tags and gauntlet's `tags` for leaf slugs.

### Oracle tag lookups (`otag:`)

Scryfall's community Oracle tags are the fastest way to answer "give me all the X". They
ship as a bulk file too, so this is also local and unlimited:

```bash
scryfall tags mana            # discover slugs matching a pattern, biggest first
scryfall otag mana-rock GUR 2 # tagged cards, filtered to a colour identity and max mana value
scryfall otag mana-dork G 1
```

`tags` exists because you rarely guess the slug right. It's `mana-rock`, not `manarock`, and
there are near-misses like `utility-mana-rock` and `mana-egg` worth seeing. **Always discover
the slug before trusting a lookup.** Useful ones: `mana-rock` (394), `mana-dork` (455),
`ramp`, `removal-exile`, `board-wipe`, `card-advantage`, `tutor`, `stax`.

Tags are hierarchical and the lookup expands children the way Scryfall does, so broad parents
work: `otag removal` returns ~6100 cards drawn from `removal-exile`, `removal-bounce` and the
rest, even though the parent tag itself has no direct taggings.

`otag` filters to Commander-legal cards and sorts by mana value. Outside Commander, that
filter drops cards that are banned there but legal in your format; query gauntlet's index
for those.

One jq footgun, since this skill pushes you toward jq: **inside `reduce`, `.` is the
accumulator, not the input root.** Capture the root first (`. as $root | reduce …`), or every
card lookup inside the loop silently returns null and you get a confident, empty answer.

Prefer one jq or `otag` pass over many API calls. Hit the live search API only for something
genuinely not in either index (rulings, prices in other currencies), and then with a
`User-Agent` header and a gap between calls. Per-card API loops got this machine a 403
"restricted" once.

There is no `bc` and no `python3` on this machine: use jq, awk and sed.

## Rules questions

Comprehensive Rules, as JSON keyed by rule number:

```bash
curl -s https://api.academyruins.com/cr -o /tmp/cr.json
jq -r 'to_entries[]|select(.key|startswith("613"))|"\(.key)  \(.value.ruleText)"' /tmp/cr.json
```

Rulings aren't in the bulk index; they're one API call per card:

```bash
curl -s -A nixconf-mtg-skill/1.0 -G https://api.scryfall.com/cards/named \
  --data-urlencode exact="Zirda, the Dawnwaker" | jq -r .rulings_uri \
  | xargs curl -s -A nixconf-mtg-skill/1.0 | jq -r '.data[].comment'
```

Answer interaction questions from oracle text, the CR and those rulings, and cite the rule
numbers. If an interaction doesn't work, say
so plainly. Being the annoying player only works if you're correct.

### Which keywords are activated abilities

Restrictions and payoffs that key off "has an activated ability" (Zirda, Lithoform-style
copying, cost reducers) are easy to get wrong, because a grep for `:` in oracle text misses
keyword abilities and misses intrinsic ones completely. Auditing a deck by hand against this
went wrong twice in one session (false-flagging Skullclamp, then Station), so start from the
list instead of re-deriving it.

**Are activated abilities** (keyword names as Scryfall spells them, so they can be matched
against the index's `keywords` array): `Cycling`, `Equip`, `Crew`, `Reconfigure`, `Station`,
`Unearth`, `Level Up`, `Channel`, `Ninjutsu`, `Outlast`, `Adapt`, `Monstrosity`, `Boast`,
`Exhaust`, `Forecast`, `Transmute`, `Scavenge`, `Embalm`, `Eternalize`.

**Are not**, despite looking like it:

- `Suspend`: static plus two triggered abilities (CR 702.62). Cost reducers don't touch it
  and it doesn't satisfy an activated-ability requirement.
- `Flashback`, `Evoke`, `Prototype`: alternative costs / casting permissions, not abilities.
- `Morph`, `Megamorph`: turning a face-down permanent up is a *special action*.
- Anything phrased "when/whenever/at" (triggered) or with no cost at all (static). **Sun Titan
  is triggered**, so it fails an activated-ability restriction even though it reads like a
  classic recursion engine.

Two more traps:

- **Intrinsic abilities count and are invisible to a text search.** Any land with a basic land
  type has intrinsic mana abilities, so duals and Triomes qualify without printing a `:`.
- **Granted abilities aren't printed characteristics.** A card that *gives* other cards cycling
  doesn't itself have cycling. An ability granted while a card was in hand doesn't follow it to
  the graveyard, which is how a "count cards with cycling in your graveyard" payoff can quietly
  read zero.

## Design brief: build the deck the judge dreads

Alex is a nerdy player first. The goal is **weird, funny, rules-bending interactions**, to
spiritually be the person the judge is annoyed with. Register examples: a Splice onto Arcane
deck, a colourless Gates deck, Lantern-style topdeck control. Aim there by default, in any
format.

- **Lead with a mechanical hook, not a tribe.** "Splice onto Arcane" is a great starting
  point; "elves, but good" is not. Forgotten and awkward mechanics are the raw material:
  Splice, Forecast, Vanishing, Fateseal, Kicker, Storm, Foretell, Banding, Phasing,
  Companion, level-up, whatever has a strange corner.
- **Favour cards that mess with the rules layers**, not just the board: replacement effects,
  state-based actions, alternate win/lose conditions, cards that rewrite how drawing or
  casting works, topdeck manipulation, "you may play from" effects, type-changing shenanigans.
  If a card would make the table stop and re-read it, it's a candidate.
- **A deck that does something nobody has seen beats a deck that wins more.** Prefer the
  janky-but-functional line over the strictly stronger generic one. Explain the cute
  interaction when you propose it; the *why it's funny* is part of the pitch.
- **Reject goodstuff piles.** Every card is there for the plan, the joke, or the rules corner,
  never because it's a staple.
- **Satisfying a constraint is not a reason to play a card.** When a companion or theme
  imposes a restriction, the cheapest cards that technically qualify are still filler.
- **Let the engine set the curve.** If your recursion or tutor effect fetches a specific mana
  value band, cluster the deck there deliberately. Cards outside the band are dead to your own
  engine.
- **No lottery slots.** A card that only pays off when it happens to be on top, or needs three
  other pieces first, is a slot spent on variance. Cut it for something the deck does every
  game.
- **Still make it work.** Fixing, ramp and interaction still get their slots. The bar is
  "genuinely functional *and* deeply strange", not "strange".

## Building a list

- **Fill each role from a search, then pick.** Pull candidates from the index, otags and
  `lands` before choosing. Recall misses new cards.
- **Read every card a query surfaces before dismissing it.**
- **Categories are measurement inputs.** Gauntlet queries run on `cat:`, so a card filed
  under a role it doesn't do inflates a pass rate. A category names a mechanism the card's
  oracle text has: a damage doubler is not a "Discard Payoff". Split enablers from payoffs.
- **Check the turn it matters.** Before a claim about a card's role, check its cost and
  timing on that turn: a 4-mana ramp spell is not a turn-2 play; scry before a dredge draw
  sees nothing; permanents cast from the graveyard are still sorcery speed.
- **Cuts are named.** Every change lists cuts as well as adds. Never cut a card silently,
  never substitute for a card the user named, and when a remark is ambiguous ("not okay",
  "never happening") ask before cutting on it.
- **Answer what was asked.** "Is there something there?" wants ideas, not a full list.

### Manabase: picked from a list, never recalled

Manabases from memory come out as precon filler: gainlands, temples, zero MDFCs.

- **Start from `scryfall lands <ci>`**, not recall. It lists every land and MDFC in the
  identity, MDFCs first, then by untapped → conditional → tapped. (It filters on Commander
  legality; outside Commander, check what it lists against gauntlet's index.)
- **MDFCs are spells that cost no land slot.** Fill spell roles with MDFCs wherever one does
  the job. In hand an MDFC is only its front face, so it is not a land *card* for "discard a
  land" / "put a land from your hand" effects.
- **Untapped where the curve needs it.** The colour of turns 1–2 gets the untapped sources.
  A tapland earns its slot by doing something (cycling, bounce, a triome's fixing).
- **Sources follow pips relative to mana value.** `{R}{R}{R}` on a 3-drop is a different
  problem from `{2}{R}{R}{R}` on a 5-drop. `gauntlet`'s `can_cast` is the measurement.
- **Basics feed basic-fetch ramp.** Cultivate and friends take two basics each, and fetchlands
  compete for the same pool.

## Where decks live: `~/code/mtg`

A git repo. `decks/<slug>.deck.toml` is the deck, `collection.toml` is what the user owns,
and saving is a commit plus push (history is the undo). Criteria files go beside the deck as
`decks/<slug>.criteria.toml`. Never leave a list in `/tmp` or `~`; always state the path.

`.deck.toml` is progress-engine's format: `cards = [{ printing = "set/num" | name = "…",
qty?, in = ["Category", …] }]` plus a `[categories]` table, and optional
`name`/`description` at the top. Edit it in place for changes. For a new deck, write
Archidekt text (below) and convert:

```bash
gauntlet import new.txt > ~/code/mtg/decks/<slug>.deck.toml
```

`check`, `play` and `gauntlet test` all read `.deck.toml` directly. Printing-only entries
are named from gauntlet's index, which needs printings: run `gauntlet sync` once if `parse`
says so.

A failed edit command leaves the old file in place, so a passing test after an error is a
pass on the old list. Re-run after any edit that printed an error.

### Archidekt text format

Used for new decks before `import`, and for showing a full list. One card per line:

```
4x Card Name [Category]
1x Other Card [Category,Other Category]
```

- **Omit set codes, collector numbers and foil markers.** Quantity and name are the only
  required parts; leaving the rest out avoids pinning the user to an expensive printing.
- **Always include `[Category]`.** Functional groupings are the point, and they're what
  `gauntlet` queries. Mirror the user's existing category names when editing a list.
- **Category names must say what the cards do.** Invented flavour names ("Cycling Jackpot")
  hide what the slot is for, and a category you can't name functionally usually means the
  cards don't share a real role.
- **A card can carry several categories**, comma-separated, when it genuinely does two jobs.
  Don't scatter categories to pad the list.
- `[Sideboard]` / `[Maybeboard]` categories, or a `{noDeck}` flag, keep cards out of the
  deck proper.
- For changes to a deck in the repo, edit the `.deck.toml`, commit, push, and reply with a
  cuts/adds table and the reasoning. Print the full list for a new build or when asked.

## Playtest it: `scryfall play`

A legal list says nothing about whether the deck *functions*: whether the colour sources
support the curve, whether the engine assembles, whether the opening hands are playable.
For that, deal it and play it out.

`play` is a shuffled deck plus honest zone bookkeeping. It is **not** a rules engine: it owns
the randomness and where every card is, and you make every decision out loud. There is no
mana pool, stack, priority or combat, on purpose. A harness that tracked those would invite
you to assert a line worked instead of demonstrating it.

```bash
scryfall play new deck.toml --seed 42  # shuffle, commander (if any) to the command zone, draw seven
scryfall play state                    # every zone, with type line and mana value
scryfall play draw [n]                 # draw n (default 1)
scryfall play mull                     # London: fresh seven, N owed to the bottom
scryfall play peek [n]                 # look at the top n without moving them (scry)
scryfall play top|bottom <card> [--from <zone>]   # reorder; --from library after a scry
scryfall play move <card> <zone> [--from <zone>] [--tapped]
scryfall play tap|untap <card>
scryfall play turn [--no-draw]         # untap everything, next turn, draw
scryfall play counter <card> <kind> <delta>
scryfall play log                      # every action taken, in order
scryfall play end
```

Zones are `library`, `hand`, `battlefield`, `graveyard`, `exile`, `command`. Every subcommand
takes `--name <G>` so several games can run at once.

- **`move` is the workhorse.** Without `--from` it searches hand, battlefield, command,
  graveyard, exile in that order and takes the first match. The library is deliberately *not*
  searched, since it holds copies of most cards. Use `--from library` to tutor something out.
- **`counter` takes any counter kind**, so storage, charge and +1/+1 counters coexist.
  `turn` untaps everything and leaves counters alone.
- **`--seed` makes a deal reproducible**, which turns "this hand was bad" into a repeatable
  bench you can re-run after changing the list.
- **State is real and persists** between invocations, under
  `${XDG_STATE_HOME:-~/.local/state}/scryfall/games/`. `play log` is the audit trail; quote it
  rather than describing a line from memory.

### Do not touch the shuffler without re-running the bias check

Randomness here is `shuf`, never a hand-rolled PRNG. Two prototypes were rejected for
producing confident wrong numbers:

| Approach | Result |
|---|---|
| LCG shuffle in jq | 82% of opening hands had exactly 1 land. Correct answer: 16.4%. |
| `awk srand()` keystream into `--random-source` | Mean 2.3195 lands in seven vs. a true 2.5457, eight standard errors low. |

The acceptance test is the hypergeometric distribution for the deck. For 36 lands in 99 cards,
n=7: **mean 2.5457, SD 1.2331**. Deal N hands, count lands, and check the mean sits within
~3 SE (`1.2331/sqrt(N)`). Both `shuf` and the seeded openssl AES-CTR keystream clear this;
anything you replace them with must too.

## Test whether it functions: `gauntlet`

`play` deals one game. The question that decides whether a deck works is **by turn N, how
often do I actually have the pieces**, where a "piece" may be one card or two combined, and
one card can count as several.

`gauntlet test` answers that exactly. It doesn't simulate: it groups cards by which of your
queries they match and enumerates the possibilities, so there is no sampling error and no
shuffler to bias.

```bash
gauntlet parse <deck>              # the canonical decklist parser, as JSON (.deck.toml or text)
gauntlet import deck.txt           # Archidekt text as a .deck.toml, on stdout
gauntlet sync                      # build its own index, with printings (~/.cache/scryfall/index.jsonl)
gauntlet test <deck> criteria.toml # evaluate criteria, PASS/FAIL, exit code
gauntlet test <deck> c.toml --draw # model being on the draw
```

Criteria are TOML. All `require` clauses must hold; `[[criterion.any_of]]` branches are
alternatives. `can_cast` prices a cost against the lands drawn (rocks and dorks don't count,
and shock/check lands are assumed tapped, so mana figures are floors). Worked examples:
`~/code/progress-engine/decks/*.criteria.toml`.

```toml
# turn 0 is the opening hand; on the play turn 1 draws nothing.
[[criterion]]
name = "engine online by turn 3"
at_least = 0.50
require = [
  { turn = 2, query = 'cat:"Ramp"', min = 1 },
  { turn = 3, can_cast = "{2}{U}{U}" },
]

[[expect]]          # a mean and distribution, never fails
name = "lands in opener"
turn = 0
query = "t:land"
```

Card selection is a subset of Scryfall syntax (`t:land`, `o:"Add {W}"`, `mv<=2`, `id<=W`,
`is:permanent`, `-t:creature`, `or`, parentheses) plus `cat:"..."` for the decklist's own
categories. **Unsupported syntax is a parse error naming the term**, never a silent no-match.

- **A criterion without `at_least` is informational.** It reports a number and cannot fail.
  Use thresholds for the things the deck genuinely needs.
- **The file decides how many turns to model.** The deepest `turn` you ask about sets it.
- **Watch the query match counts.** Every run reports how many cards each query matched, and
  says so loudly when that is zero. A misspelled category parses fine and matches nothing,
  which yields a confident 0%. That is the failure this tool can't refuse for you.
- **Check the library size in the output.** If it's higher than the deck should be,
  something that belongs outside the deck is being counted: mark sticker sheets `[Sideboard]`
  or flag them `{noDeck}`, since a bare `[Stickers]` category is not a signal any parser can
  read.
- **`--simulate` is an escape hatch, not an upgrade.** It is slower and approximate, and it
  reports standard errors because you should not quote a sampled figure without one.

Ask about budget and format if they weren't stated. Prices are in the index (`usd`).
