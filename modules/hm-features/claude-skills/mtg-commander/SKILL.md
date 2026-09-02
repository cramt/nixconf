---
name: mtg-commander
description: 'Use when building, upgrading, critiquing or discussing Magic: The Gathering Commander/EDH decks — "build me a commander deck", "brew around X", "upgrade this list", "what bracket is this", "is this card legal in my colors", "swap some cards in this deck". Covers Scryfall lookups, the Commander bracket system, ramp curve tuning, and Archidekt-format output.'
---

# MTG Commander deckbuilding

## The one non-negotiable rule: Scryfall is the source of truth

**Never answer a card question from memory.** Two independent reasons, both sufficient:

1. Magic prints thousands of cards a year. Anything past your cutoff simply isn't in you.
2. Even for cards you "know", you are a model, not a database. Oracle text gets errata'd, cards get banned and unbanned, and the Game Changers list has been revised four times since it launched. Confident recall is not the same as correct recall.

Concretely, you do not know and must look up: whether a card exists, its current oracle text, mana cost, colour identity, Commander legality, Game Changer status, or price.

A worked example of why: the bracket system originally restricted tutors at brackets 1–3. That restriction was **removed entirely** in October 2025. An agent working from memory would confidently enforce a rule that no longer exists.

## Use bulk data, not the search API

Scryfall asks callers to stay under ~10 requests/sec with a 50–100ms gap. Resolving a
100-card decklist one `/cards/named` call at a time is slow, rude, and gets rate limited.
Scryfall's answer to this is the bulk data files, and there's a helper wrapping them:

```bash
scryfall sync                     # refresh cached indexes (automatic, at most once/day)
scryfall card "Rhystic Study"     # one card's deck-relevant fields
scryfall gamechangers             # the live Game Changers list
scryfall check <file> [bracket]   # validate a decklist; PASS/FAIL to stderr, exit code, JSON to stdout
scryfall tags [pattern]           # find Oracle tag slugs
scryfall otag <slug> [ci] [cmc]   # cards carrying an Oracle tag
scryfall path                     # path to the index, for arbitrary jq
scryfall play new <file>          # deal a real shuffled deck and play it out
```

A second binary, `progress-engine`, answers the question neither of those does — how often the
deck actually has its pieces by turn N. See [Test whether it functions](#test-whether-it-functions-progress-engine).
It also owns decklist parsing outright: `check` and `play` shell out to it, so all three agree
on what a decklist is by construction.

The first `sync` takes about a minute and then serves everything from disk. Each card record
is `{name, ci, commander_legal, game_changer, type_line, cmc, keywords, oracle, any_number,
usd, uri}`, keyed by lowercased name under `.cards`, so open-ended questions are a jq away
with **zero** API calls:

```bash
# every 1-mana green creature that could plausibly be a mana dork
jq -r '[.cards|to_entries[]|select(.value.ci==["G"] and .value.cmc==1
        and (.value.type_line|test("Creature")))|.value.name]|sort|.[]' "$(scryfall path)"
```

The index carries full `oracle` text (both faces) and `keywords`, which makes mining an
obscure mechanic — the main thing this skill is for — a local grep:

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

### Oracle tag lookups (`otag:`)

Scryfall's community Oracle tags are the fastest way to answer "give me all the X" — and they
ship as a bulk file too, so this is also local and unlimited:

```bash
scryfall tags mana            # discover slugs matching a pattern, biggest first
scryfall otag mana-rock GUR 2 # tagged cards, filtered to a colour identity and max mana value
scryfall otag mana-dork G 1
```

`tags` exists because you rarely guess the slug right — it's `mana-rock`, not `manarock`, and
there are near-misses like `utility-mana-rock` and `mana-egg` worth seeing. **Always discover
the slug before trusting a lookup.** Useful ones: `mana-rock` (394), `mana-dork` (455),
`ramp`, `removal-exile`, `board-wipe`, `card-advantage`, `tutor`, `stax`.

Tags are hierarchical and the lookup expands children the way Scryfall does, so broad parents
work: `otag removal` returns ~6100 cards drawn from `removal-exile`, `removal-bounce` and the
rest, even though the parent tag itself has no direct taggings.

`otag` filters to Commander-legal cards and sorts by mana value, so its output is already
deck-shaped.

One jq footgun, since this skill pushes you toward jq: **inside `reduce`, `.` is the
accumulator, not the input root.** Capture the root first (`. as $root | reduce …`), or every
card lookup inside the loop silently returns null and you get a confident, empty answer.

Prefer one jq or `otag` pass over many API calls; hit the live search API only
for something genuinely not in the bulk files, and then with a `User-Agent` header and a gap
between calls.

## Design brief: build the deck the judge dreads

Alex is a nerdy player first. The goal is **weird, funny, rules-bending interactions** — to
spiritually be the person the judge is annoyed with. Register examples: a Splice onto Arcane
deck, a colourless Gates deck, Lantern-style topdeck control. Aim there by default.

What this means in practice:

- **Lead with a mechanical hook, not a tribe.** "Splice onto Arcane" is a great starting
  point; "elves, but good" is not. Forgotten and awkward mechanics are the raw material —
  Splice, Forecast, Vanishing, Fateseal, Kicker, Storm, Foretell, Banding, Phasing,
  Companion, level-up, whatever has a strange corner.
- **Favour cards that mess with the rules layers**, not just the board: replacement effects,
  state-based actions, alternate win/lose conditions, cards that rewrite how drawing or
  casting works, topdeck manipulation, "you may play from" effects, type-changing shenanigans.
  If a card would make three players stop and re-read it, it's a candidate.
- **A deck that does something nobody has seen beats a deck that wins more.** Prefer the
  janky-but-functional line over the strictly stronger generic one. Explain the cute
  interaction when you propose it — the *why it's funny* is part of the pitch.
- **Reject goodstuff piles.** Do not fill slots with staples because they're staples. Every
  card should be there for the plan, the joke, or the rules corner. (This is the same instinct
  behind the Sol Ring rule below.)
- **Satisfying a constraint is not a reason to play a card.** When a companion or theme
  imposes a deckbuilding restriction, the cheapest cards that technically qualify are still
  filler. A deck full of 1-mana artifacts "because they all have activated abilities" is a
  worse deck than one where every artifact also advances the plan.
- **Let the engine set the curve.** If your recursion or tutor effect fetches a specific mana
  value band, cluster the deck there deliberately — an effect that returns MV≤3 permanents
  or grabs an MV 2–3 artifact makes the whole curve a design parameter, not an afterthought.
  Cards outside the band are dead to your own engine.
- **No lottery slots.** A card that only pays off when it happens to be on top, or needs three
  other pieces first, is a slot you spent on variance. Cut it for something the deck does
  every game.
- **Still make it work.** Nerdy is not an excuse for a deck that can't cast its spells.
  Fixing, ramp and interaction still get their slots — the bar is "genuinely functional *and*
  deeply strange", not "strange".
- **Get the rules right.** When a build leans on an obscure interaction, verify it against
  actual oracle text (and Scryfall's rulings if needed) rather than vibes. Being the annoying
  player only works if you're correct — if an interaction doesn't actually work, say so.

## The bracket system

Five brackets, set by WotC's Commander Format Panel. Still officially "beta" — the tag may
drop during 2026. Rules below were current as of **August 2026**; if the conversation
touches an edge case, re-check the official announcements, and get the Game Changers list
from `scryfall gamechangers` rather than any list written down here.

| # | Name | Game Changers | Mass land denial | Extra turns | Two-card infinite combos | Games usually last |
|---|------|---------------|------------------|-------------|--------------------------|--------------------|
| 1 | Exhibition | 0 | no | no | none intentional | 9+ turns |
| 2 | Core | 0 | no | a few, never chained or looped | none intentional | 8+ turns |
| 3 | Upgraded | up to 3 | no | low counts, never chained or looped | none cheap/early; a turn-6-or-later combo finish is fine | 6+ turns |
| 4 | Optimized | unlimited | allowed | allowed | allowed | 4+ turns |
| 5 | cEDH | unlimited | allowed | allowed | allowed | any turn |

Cross-bracket notes:

- **Tutors are unrestricted at every bracket.** Removed October 2025 — the reasoning was
  that the format's best tutors are already on the Game Changers list.
- **Mass land denial** means destroying, exiling, bouncing, tapping down or otherwise
  altering the mana of **four or more lands per player without replacing them**. Armageddon,
  Winter Orb and Blood Moon are the canonical examples. Absent from brackets 1–3.
- **Game Changers set a floor, never a ceiling.** One Game Changer means the deck cannot be
  bracket 1 or 2. Four means it is bracket 4 by rule, even if it plays like a 3.
- **Brackets 4 and 5 share a rules set**; the difference is mindset. Bracket 5 is
  metagame-aware and competitive — pet cards give way to staples, winning outweighs
  self-expression.
- **"Intentional" is load-bearing.** The lower brackets bar combos and extra-turn chains you
  *built toward*; stumbling into one mid-game is fine.
- **Bracket 1 can bend legality** by table agreement (un-cards and similar).
- **Rule Zero still overrides everything.** Brackets are a shorthand for the pregame
  conversation, not a replacement for it.

Always state the target bracket up front and justify it. Flag honestly when a deck's
*rules-legal* bracket and its *actual feel* diverge.

## Ramp: tune it to the commander's cost

Generic "good ramp" is a trap. **A ramp card earns its slot only if it advances the turn you
actually deploy your commander** (or the deck's key engine). Count the turns out; don't
eyeball it.

| Commander CMC | Ramp that works | Why |
|---------------|-----------------|-----|
| 3 | 1-mana accelerant (mana dork, 1-mana rock) | T1 dork → T2 you have 2 lands + dork = 3 → commander on **T2** |
| 4 | 2-mana rock, or 2-mana "search up a land" | T2 rock → T3 = 4 mana → commander on **T3**. 1-mana accelerants also work |
| 5 | 1-mana accelerant **plus** 3-mana ramp that also draws | T1 dork, T2 (3 mana) cast it → lands a land and puts one in hand → T3 = 4 lands + dork = 5 → commander on **T3** |

The counter-example that makes the principle click: **a 2-mana rock in a 3-drop commander
deck does nothing.** Play the rock on T2 and you cast your commander on T3 — exactly when
you'd have cast it off untapped lands anyway. You spent a card to accomplish nothing.

Note also how ramp compounds: the 1-mana accelerant is what lets the 3-mana ramp spell come
down a turn early, which is why the 5-drop line gains two full turns rather than one.

Those are **archetypes, not card recommendations.** There are hundreds of 1-mana creatures
that tap for a mana, hundreds of 2-mana rocks and land-fetch sorceries, and plenty of 3-mana
"fetch a land, put another in hand" effects. Pick ones that fit the colours and the plan —
and look them up:

```bash
scryfall otag mana-dork G 1     # 1-mana accelerants in green
scryfall otag mana-rock GUR 2   # 2-mana rocks castable in Temur
```

## House rules

- **No Sol Ring in bracket 1–3 decks.** Not a playgroup rule and not a power argument — a
  variance one. A turn-one Sol Ring either runs away with the game or paints you as the
  table's archenemy, and neither outcome is a fun coinflip. It's fine at bracket 4+, where
  everyone opted into that, but those decks are rare here. `scryfall check` enforces this at
  brackets ≤3 and lifts it at 4+.

## Always output decklists in Archidekt format

Whenever a decklist comes up — a new build, an upgrade, or even a handful of swaps — give
the **complete 100-card list**, not a diff or an excerpt. One card per line:

```
1x Card Name [Category]
1x Rashmi and Ragavan [Commander{top}]
```

- **Omit set codes, collector numbers and foil markers.** `(otc)`, `271` and `*F*` are all
  optional on import; leaving them out lets Archidekt pick a printing and avoids pinning the
  user to a specific (possibly expensive) version. Quantity and name are the only required
  parts.
- **Always include `[Category]`** — functional groupings are the point. Use the categories
  the deck actually wants (`Interaction`, `Draw`, `Ramp`, `Tutor Package`, `Land - Fixing`,
  `Land - Utility`, `Recursion`, `Graveyard Police`, and theme-specific ones). Mirror the
  user's existing category names when editing an existing list.
- **Category names must say what the cards do.** A category has to be obvious to someone
  reading the list cold. Invented flavour names ("Cycling Jackpot") hide what the slot is for
  — and a category you can't name functionally is usually a sign the cards don't share a real
  role, which is worth noticing before the list ships.
- **A card can carry several categories**, comma-separated inside the brackets:
  `1x Myr Battlesphere [Big Colorless,Test]`. Use this when a card genuinely does two jobs —
  it is what lets `odds` ask about either role — but don't scatter categories to pad the list.
- The commander goes in a `[Commander{top}]` category. It may sit alongside others
  (`[Ramp,Commander{top}]`) and still registers as the commander.
- For upgrades, print the full new list, then a short cuts/adds table underneath explaining
  the reasoning. The list first, the prose second.

## Before presenting any list, validate it

Run `scryfall check <file> <bracket>` and resolve everything it reports. It catches the
failure modes that actually matter:

- `unknown` — **a hallucinated or misspelled card.** Never ship a list with these.
- `illegal` — banned or not legal in Commander.
- `color_identity_violations` — computed from the card's `color_identity` field, which is the
  only correct source. Do not infer identity from the mana cost: reminder text, activated
  ability costs and the back face of an MDFC all contribute.
- `singleton_violations` — duplicates that aren't basic lands or cards whose own text allows
  any number.
- `total` — must be exactly 100 including the commander.
- `house_ban_violations` and `game_changer_count` → bracket floor.

**Read the verdict, not a projection of it.** `check` prints `PASS` or a one-line
`FAIL: …` to **stderr** and exits non-zero, precisely because piping stdout through
`jq '{total, unknown, illegal}'` can silently drop the field that failed. That has happened:
a deck with 35 colour identity violations was reported as validated because the projection
omitted `color_identity_violations`. If you filter the JSON, still read stderr.

Also: **card count comes from `.total`, never `wc -l`.** Lines and cards differ the moment
the list has a `3x Plains`.

The script cannot see mass land denial, cheap combos, chained extra turns, or the
deckbuilding restriction a companion imposes — it lists these in `.unchecked`. Those need
you to actually read the deck, so check them by hand before claiming a bracket.

`.usd_total` and `.priciest` come out of the same pass, so don't shell out for arithmetic —
there is no `bc` on this machine.

### Partners, backgrounds and companions

- **Two commanders**: give each its own `[Commander{top}]` line. Colour identity is the
  **union** of both, and `check` computes it that way — a Doctor + Doctor's-companion pair
  like The Fifteenth Doctor (UR) + Jo Grant (W) is a WUR deck.
- **A companion is a 101st card, not one of the 100** (CR 903.11) — and it must still be
  inside the commanders' colour identity. Put it on its own line in a category matching
  `Companion`/`Sideboard`/`Maybeboard` or carrying a `noDeck` flag; `check` then excludes it
  from `.total` and reports it under `.companion`.
- **The companion's own restriction reaches the command zone.** Zirda demands that every
  permanent card in the starting deck have an activated ability, and the ruling is explicit
  that this includes your commander. Verify that restriction card by card against oracle
  text — nothing automated does it for you, and watch for cards that satisfy it *intrinsically*
  rather than via a printed `:` (a dual land with basic land types has intrinsic mana
  abilities, so a naive colon-grep gives false negatives).
- Archidekt's category flags for "don't count this toward the deck" are an internal property
  rather than a documented import modifier, so don't promise that a `{noDeck}` line will
  import correctly. Say plainly that the companion is the 101st card and may need setting in
  the UI.

## Playtest it: `scryfall play`

`check` proves a list is legal. It says nothing about whether the deck *functions* — whether
the colour sources support the curve, whether the engine assembles, whether the opening hands
are playable. For that, deal it and play it out.

`play` is a shuffled deck plus honest zone bookkeeping. It is **not** a rules engine: it owns
the randomness and where every card is, and you make every decision out loud. There is no mana
pool, stack, priority or combat, on purpose — a harness that tracked those would invite you to
assert a line worked instead of demonstrating it.

```bash
scryfall play new deck.txt --seed 42   # shuffle, commander to the command zone, draw seven
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

Notes that matter in practice:

- **`move` is the workhorse.** Without `--from` it searches hand, battlefield, command,
  graveyard, exile in that order and takes the first match. The library is deliberately *not*
  searched — it holds copies of most cards, so including it made almost every move ambiguous.
  Use `--from library` to tutor something out.
- **`counter` takes any counter kind**, so storage, charge and +1/+1 counters coexist:
  `play counter "City of Shadows" storage +1`. `turn` untaps everything and leaves counters
  alone.
- **`--seed` makes a deal reproducible**, which is what turns "this hand was bad" into a
  repeatable bench you can re-run after changing the list. Without it you get a fresh deal
  from urandom.
- **State is real and persists** between invocations, under
  `${XDG_STATE_HOME:-~/.local/state}/scryfall/games/`. `play log` is the audit trail; quote it
  rather than describing a line from memory.

### Do not touch the shuffler without re-running the bias check

Randomness here is `shuf`, never a hand-rolled PRNG. Two prototypes were written and rejected
for producing confident wrong numbers:

| Approach | Result |
|---|---|
| LCG shuffle in jq | 82% of opening hands had exactly 1 land. Correct answer: 16.4%. |
| `awk srand()` keystream into `--random-source` | Mean 2.3195 lands in seven vs. a true 2.5457 — eight standard errors low. |

The acceptance test is the hypergeometric distribution for the deck. For 36 lands in 99 cards
(a 100-card deck minus the commander), n=7: **mean 2.5457, SD 1.2331**. Deal N hands, count
lands, and check the mean sits within ~3 SE (`1.2331/sqrt(N)`). Both `shuf` and the seeded
openssl AES-CTR keystream clear this; anything you replace them with must too.
## Test whether it functions: `progress-engine`

`check` proves a list is legal. `play` deals one game. Neither answers the question that
decides whether a deck works: **by turn N, how often do I actually have the pieces** — where a
"piece" may be one card or two combined, and where one card can count as several.

`progress-engine test` answers that exactly. Not by simulating: it groups cards by which of
your queries they match and enumerates the possibilities, so there is no sampling error and no
shuffler to bias.

```bash
progress-engine parse deck.txt              # the canonical decklist parser, as JSON
progress-engine test deck.txt criteria.js   # evaluate criteria, PASS/FAIL, exit code
progress-engine test deck.txt c.js --draw   # model being on the draw
progress-engine test deck.txt c.js --simulate --trials 200000 --seed 1
```

Criteria are JavaScript, so combining requirements is ordinary code:

```js
// t(n) is your position on turn n; t(0) is the opening hand. On the play, turn 1
// draws nothing, so t(0) and t(1) see the same seven cards.
criterion("turn-1 accelerant", (t) =>
  t(1).count('t:land') >= 1 &&
  t(1).count('cat:"Ramp - One Mana"') >= 1,
  { atLeast: 0.35 });

// The bar for a three-mana commander getting down on turn two.
criterion("commander on turn 2", (t) =>
  t(1).count('t:land') >= 1 &&
  t(1).count('cat:"Ramp - One Mana"') >= 1 &&
  t(2).count('t:land') >= 2,
  { atLeast: 0.30 });
```

Card selection is a subset of Scryfall syntax — `t:land`, `o:"Add {W}"`, `mv<=2`, `id<=W`,
`is:permanent`, `-t:creature`, `or`, parentheses — plus `cat:"..."` for the decklist's own
categories. **Unsupported syntax is a parse error naming the term**, never a silent no-match.

Notes that matter in practice:

- **A criterion without `atLeast` is informational.** It reports a number and cannot fail.
  Use thresholds for the things the deck genuinely needs, not for everything.
- **The file decides how many turns to model.** The deepest `t(n)` you ask about sets it;
  nothing is declared twice.
- **Watch the query match counts.** Every run reports how many cards each query matched, and
  says so loudly when that is zero. A misspelled category parses fine and matches nothing,
  which yields a confident 0% rather than a complaint — that is the failure this tool exists
  to catch, and it is the one it cannot refuse for you.
- **Check the library size in the output.** It should be 99 for a normal Commander deck. If
  it is higher, something that belongs outside the deck is being counted: mark sticker sheets
  `[Sideboard]` or flag them `{noDeck}`, since a bare `[Stickers]` category is not a signal
  any parser can read.
- **`--simulate` is an escape hatch, not an upgrade.** It is slower and approximate, and it
  reports standard errors precisely because you should not quote a sampled figure without
  one. Prefer the exact default; the sampled engine exists mainly to keep the exact one honest.

The same binary is what `check` and `play` use to read decklists, so all three agree on what
a decklist is by construction rather than by comment.


## Reference: which keywords are activated abilities

Restrictions and payoffs that key off "has an activated ability" (Zirda, Lithoform-style
copying, cost reducers) are easy to get wrong, because a grep for `:` in oracle text misses
keyword abilities entirely and misses intrinsic ones completely. Auditing a deck by hand
against this went wrong twice in one session — false-flagging Skullclamp, then Station — so
start from the list instead of re-deriving it.

**Are activated abilities** (keyword names as Scryfall spells them, so they can be matched
against the index's `keywords` array): `Cycling`, `Equip`, `Crew`, `Reconfigure`, `Station`,
`Unearth`, `Level Up`, `Channel`, `Ninjutsu`, `Outlast`, `Adapt`, `Monstrosity`, `Boast`,
`Exhaust`, `Forecast`, `Transmute`, `Scavenge`, `Embalm`, `Eternalize`.

**Are not**, despite looking like it:

- `Suspend` — static plus two triggered abilities (CR 702.62). Cost reducers don't touch it
  and it doesn't satisfy an activated-ability requirement.
- `Flashback`, `Evoke`, `Prototype` — alternative costs / casting permissions, not abilities.
- `Morph`, `Megamorph` — turning a face-down permanent up is a *special action*.
- Anything phrased "when/whenever/at" (triggered) or with no cost at all (static). **Sun Titan
  is triggered**, so it fails an activated-ability restriction even though it reads like a
  classic recursion engine.

Two more traps worth knowing:

- **Intrinsic abilities count and are invisible to a text search.** Any land with a basic land
  type has intrinsic mana abilities, so duals and Triomes qualify without printing a `:`.
- **Granted abilities aren't printed characteristics.** A card that *gives* other cards cycling
  doesn't itself have cycling, so it fails the check — and an ability granted while a card was
  in hand doesn't follow it to the graveyard, which is how a "count cards with cycling in your
  graveyard" payoff can quietly read zero.

## Deckbuilding defaults

Reasonable starting ratios for a bracket 2–3 deck, to adjust rather than obey:

- **35–38 lands**, trending lower with lots of cheap ramp or many MDFC land-backs (count
  those as roughly half a land each). **But go up, not down, when lands are also spells:** a
  cycling deck wants **~39**, run liberally on MDFCs and cycling lands, because a land that
  cycles is never a flooded draw. Same logic for landcycling — basic landcycling on something
  like Ash Barrens is still cycling, so it triggers every cycling payoff *and* fetches a land.
  Don't argue the count down on "flood turns into cards" grounds; that reasoning is what makes
  the extra lands correct in the first place.
- **~10 ramp pieces**, chosen by the curve rule above
- **~10 card advantage** sources — repeatable engines beat one-shot draw
- **8–12 interaction** spells, including 2–3 board wipes; make sure some of it answers
  artifacts, enchantments and graveyards, not just creatures
- the remainder on the theme and its payoffs

Ask about budget and bracket if they weren't stated — both massively change the answer, and
prices are in the index (`usd`) when they matter.
