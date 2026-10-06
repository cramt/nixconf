---
name: mtg-commander
description: 'Use when building, upgrading, critiquing or discussing Magic: The Gathering Commander/EDH decks — "build me a commander deck", "brew around X", "upgrade this list", "what bracket is this", "is this card legal in my colors", "swap some cards in this deck". Covers the Commander bracket system, EDHREC data, ramp tuned to the commander''s cost, `scryfall check` validation, partners/companions and Commander ratios. Builds on the mtg skill.'
---

# MTG Commander deckbuilding

**Load the `mtg` skill first if it isn't already loaded.** It carries the rules this one
assumes: Scryfall is the source of truth and nothing about a card comes from memory, plus
the `scryfall` CLI, the design brief, list-building and manabase rules, `~/code/mtg` and the
deck format, `scryfall play` and `gauntlet`. This skill adds only what is specific to
Commander.

What changes in Commander, and why it needs re-checking rather than recall: the bracket
system originally restricted tutors at brackets 1–3. That restriction was **removed
entirely** in October 2025. An agent working from memory would confidently enforce a rule
that no longer exists. The Game Changers list has been revised four times since launch;
get it from `scryfall gamechangers`, never from a list written down anywhere.

## What good builders agree on: read `principles.md`

[`principles.md`](principles.md), next to this file, condenses about 1000 videos from The
Trinket Mage, 3/3 Elk, Salubrious Snail, Maldhound and the Good Time Boys podcast (VeggieWagon
and co-hosts) into cited deckbuilding principles, the points where they disagree, and card
verdicts with reasons. **Read it before building, upgrading or critiquing a deck.** Use it to
judge cards and ratios, and name the principle when you apply one ("cutting Cultivate: turn 3
is too valuable outside a 1-3-5 curve").

**When rules conflict, the more specific one wins.** Alex's house rules and the design brief
beat everything. Next come this skill and `principles.md`, which are about Commander. Last
come the general `mtg` rules, Karsten's tables included, which are about Magic in general.
A deck's own deliberate design can override a ratio when you can say why. A deck whose
removal is the prize opponents pick for it runs more removal than 8-14, and that's fine.
State the override instead of applying the ratio silently.

The rules that most often decide a build:

- **One plan; cut what doesn't push it toward a win.** A deck with two half-themes has two
  decks' worth of dead draws.
- **Fundamentals first, theme on top.** Never cut ramp, draw or removal for theme; find the
  on-theme version instead.
- **A real way to close.** Value engines without a finisher make 10-turn slogs.
- **Floor over ceiling.** Judge a card by its average game: "would I want this hellbent and
  behind?" Win-more is dead in most games.
- **Don't hinge on one piece, the commander included.** Keep functional copies and a backup
  angle on the same plan.
- **Question every staple.** Power creep outclassed many of them (three-mana removal, Fact or
  Fiction), and generic bombs flatten the rest of the deck.
- **Cheap interaction (1-2 mana) that answers every permanent type,** aimed at engines rather
  than the first body.
- **Ramp that leads somewhere:** cheap, land-based and resilient, sized to the curve, paired
  with draw.
- **Re-price for 40 life and three opponents.** Effects that hit each opponent scale; chip
  damage and 60-card mill don't.

## What people actually play: EDHREC JSON

EDHREC mirrors every page as JSON. Use it; never scrape the HTML, where a fetch returns a
lossy summary that silently drops cards.

```bash
edhrec() { curl -s -A 'Mozilla/5.0' "https://json.edhrec.com/pages/$1.json"; }

edhrec commanders/borborygmos-and-fblthp \
  | jq -r '.container.json_dict.cardlists[]? | "=== \(.header) ===",
      (.cardviews[]? | "  \(.synergy*100|round)%syn \(.name)")'
```

Slug is the card name lowercased, punctuation stripped, spaces to hyphens
(`Uril, the Miststalker` → `uril-the-miststalker`). Paths: `commanders/<slug>`,
`commanders/<slug>/<theme>`, `cards/<slug>`, `average-decks/<slug>`, `decks/<slug>`.

Negative `synergy` means the card is played *less* here than in an average deck: a cut signal.

**Individual decklists live on the other host** and need a browser User-Agent:

```bash
curl -s -A 'Mozilla/5.0' "https://edhrec.com/api/deckpreview/<urlhash>" \
  | jq -r '[.deck.cards[][][0]]|.[]'
```

`decks/<slug>.json` → `.table` is every tracked deck (`urlhash`, `price`, `salt`, `bracket`,
type counts) but carries **no cardlists**, and its facets are bracket/budget/savedate/tags
only, never card. So "which decks run card X" means fetching one `deckpreview` per deck and
filtering locally: sample a few dozen, don't sweep thousands. `json.edhrec.com` 403s on
`deckpreview`. `.table` is not in random order, so a `head -N` sample skews; say so when
quoting a rate off one.

EDHREC says what people play. Scryfall stays the authority on oracle text and legality.

Add EDHREC to the candidate search from the `mtg` skill: before presenting a list, diff it
against the commander's EDHREC synergy list and account for high-synergy cards you skipped.
Icetill Explorer was in fetched EDHREC data and still left out.

## The bracket system

Five brackets, set by WotC's Commander Format Panel. Still officially "beta"; the tag may
drop during 2026. Rules below were current as of **August 2026**. If the conversation
touches an edge case, re-check the official announcements.

| # | Name | Game Changers | Mass land denial | Extra turns | Two-card infinite combos | Games usually last |
|---|------|---------------|------------------|-------------|--------------------------|--------------------|
| 1 | Exhibition | 0 | no | no | none intentional | 9+ turns |
| 2 | Core | 0 | no | a few, never chained or looped | none intentional | 8+ turns |
| 3 | Upgraded | up to 3 | no | low counts, never chained or looped | none cheap/early; a turn-6-or-later combo finish is fine | 6+ turns |
| 4 | Optimized | unlimited | allowed | allowed | allowed | 4+ turns |
| 5 | cEDH | unlimited | allowed | allowed | allowed | any turn |

- **Tutors are unrestricted at every bracket.** Removed October 2025, on the reasoning that
  the format's best tutors are already Game Changers.
- **Mass land denial** means destroying, exiling, bouncing, tapping down or otherwise
  altering the mana of **four or more lands per player without replacing them**. Armageddon,
  Winter Orb and Blood Moon are the canonical examples. Absent from brackets 1–3.
- **Game Changers set a floor, never a ceiling.** One Game Changer means the deck cannot be
  bracket 1 or 2. Four means it is bracket 4 by rule, even if it plays like a 3.
- **Brackets 4 and 5 share a rules set**; the difference is mindset. Bracket 5 is
  metagame-aware and competitive.
- **"Intentional" is load-bearing.** The lower brackets bar combos and extra-turn chains you
  *built toward*; stumbling into one mid-game is fine.
- **Bracket 1 can bend legality** by table agreement (un-cards and similar).
- **Rule Zero still overrides everything.** Brackets are a shorthand for the pregame
  conversation, not a replacement for it.

Always state the target bracket up front and justify it. Flag honestly when a deck's
*rules-legal* bracket and its *actual feel* diverge.

## House rules

- **Sol Ring is treated as banned, at every bracket.** A variance argument, not a power one,
  and a lesson taken from the creators in `mtg-lore`: a turn-one Sol Ring either runs away
  with the game or paints you as the table's archenemy, and neither is a fun coinflip.
  `scryfall check` fails any deck that runs it.

## Ramp: tune it to the commander's cost

Generic "good ramp" is a trap. **A ramp card earns its slot only if it advances the turn you
actually deploy your commander** (or the deck's key engine). Count the turns out.

| Commander CMC | Ramp that works | Why |
|---------------|-----------------|-----|
| 3 | 1-mana accelerant (mana dork, 1-mana rock) | T1 dork → T2 you have 2 lands + dork = 3 → commander on **T2** |
| 4 | 2-mana rock, or 2-mana "search up a land" | T2 rock → T3 = 4 mana → commander on **T3**. 1-mana accelerants also work |
| 5 | 1-mana accelerant **plus** 2-mana land ramp (Nature's Lore, Three Visits) | T1 dork; T2 (3 mana) cast it → an untapped land → T3 = 4 lands + dork = 5 → commander on **T3**. A 3-mana ramp spell that also draws does the same on T2 and refills, but the creators' consensus is that cheap ramp wins: it leaves mana for something else on T2 |

The counter-example: **a 2-mana rock in a 3-drop commander deck does nothing.** Play it on T2
and you cast your commander on T3, exactly when you'd have cast it off untapped lands anyway.

Ramp compounds: the 1-mana accelerant is what lets the 2-mana land ramp come down on T2 with
a mana to spare, which is why the 5-drop line gains two full turns rather than one.

Those are **archetypes, not card recommendations.** Pick ones that fit the colours and the
plan, and look them up:

```bash
scryfall otag mana-dork G 1     # 1-mana accelerants in green
scryfall otag mana-rock GUR 2   # 2-mana rocks castable in Temur
```

**Every criteria file carries the commander-on-curve line from this table.** That rule was
broken in two of six builds while it sat in prose; as a criterion it fails:

```toml
[casting]
prefer = ['name:"<commander>"', 'cat:"Ramp"']   # cast the commander first, ramp when it can't

[[criterion]]
name = "commander on curve (3-drop: turn 2)"
at_least = 0.30
require = [{ turn = 2, cast = 'name:"<commander>"', min = 1 }]
```

`cast` asks the real question: was the commander actually cast by that turn. The older
proxy, "a one-mana dork in hand plus `can_cast` of its cost", only approximates it. Declare land
ramp with an `[[effect]]` and the Battlebond lands with `[assume]` (see the `mtg` skill),
or a deck that ramps with Nature's Lore reads low here. Compare list variants rather than
trusting the absolute figure.

`gauntlet`'s library size should read 99 for a normal Commander deck.

## Commander manabase

On top of the `mtg` manabase rules: every Commander manabase built from memory so far came
out as Command Tower plus precon filler and needed rebuilding by hand. A blue deck should run
Sink into Stupor before its Nth Island.

Source counts per colour come from the 99-card column of the Karsten table in the `mtg`
skill. That column assumes 41 lands (mana rocks counting as partial lands); at 36 lands,
scale it, e.g. 26 sources for a 2CC card at 41 lands is about 23 at 36.

`scryfall check` does this Karsten check for you. `.manabase.karsten` gives, per colour, the
hardest spell, the sources it needs scaled to the deck's land count (MDFCs count 0.4 toward
that count and 0.8 as a source, and X is priced at 2), and the sources the lands provide. It
also reports MDFCs run against those available, tapped lands, and basics against basic
fetchers, and prints `manabase:` warnings to stderr. Resolve them or say why not. It counts
lands only: add dorks and rocks by hand at Karsten's fractions, and re-price cards it can't
read, such as a spell you won't cast on curve or a hybrid cost (counted toward both
colours).

## Before presenting any list, validate it

Run `scryfall check <file> <bracket>` and resolve everything it reports:

- `unknown`: **a hallucinated or misspelled card.** Never ship a list with these.
- `illegal`: banned or not legal in Commander.
- `color_identity_violations`: computed from the card's `color_identity` field, the only
  correct source. Do not infer identity from the mana cost: reminder text, activated
  ability costs and the back face of an MDFC all contribute.
- `singleton_violations`: duplicates that aren't basic lands or cards whose own text allows
  any number.
- `total`: must be exactly 100 including the commander.
- `house_ban_violations` and `game_changer_count` → bracket floor.

**Read the verdict, not a projection of it.** `check` prints `PASS` or a one-line `FAIL: …`
to **stderr** and exits non-zero, because piping stdout through `jq '{total, unknown,
illegal}'` can silently drop the field that failed. That has happened: a deck with 35 colour
identity violations was reported as validated because the projection omitted
`color_identity_violations`. If you filter the JSON, still read stderr.

**Card count comes from `.total`, never `wc -l`.** Lines and cards differ the moment the
list has a `3x Plains`.

The script cannot see mass land denial, cheap combos, chained extra turns, or a companion's
deckbuilding restriction. It lists these in `.unchecked`; read the deck for them by hand
before claiming a bracket.

`.usd_total` and `.priciest` come out of the same pass, so don't shell out for arithmetic.

## Commander, partners, backgrounds and companions

- **The commander** goes in a `[Commander{top}]` category in Archidekt text. It may sit
  alongside others (`[Ramp,Commander{top}]`) and still registers as the commander. In
  `.deck.toml` that's a `Commander = { type = "commander" }` entry under `[categories]`.
- **Two commanders**: give each its own `[Commander{top}]` line. Colour identity is the
  **union** of both, and `check` computes it that way. A Doctor + Doctor's-companion pair
  like The Fifteenth Doctor (UR) + Jo Grant (W) is a WUR deck.
- **A companion is a 101st card, not one of the 100** (CR 903.11), and it must still be
  inside the commanders' colour identity. Put it on its own line in a category matching
  `Companion`/`Sideboard`/`Maybeboard` or carrying a `noDeck` flag; `check` then excludes it
  from `.total` and reports it under `.companion`.
- **The companion's own restriction reaches the command zone.** Zirda demands that every
  permanent card in the starting deck have an activated ability, and the ruling is explicit
  that this includes your commander. Verify that restriction card by card against oracle
  text, using the activated-ability reference in the `mtg` skill.
- Archidekt's "don't count this toward the deck" flag is an internal property rather than a
  documented import modifier, so don't promise that a `{noDeck}` line imports correctly. Say
  plainly that the companion is the 101st card and may need setting in the UI.

## Deckbuilding defaults

Starting ratios for a bracket 2–3 deck, to adjust rather than obey:

- **37–40 lands, counting MDFCs, cyclers and utility lands.** This is the creators'
  consensus: too few lands is the most common brewing mistake, and since lands double as
  spells the high count is cheap. Go to 34–36 only with heavy cheap draw and filtering or 20+
  ramp (Karsten: a non-mythic land/spell MDFC is 0.40 of a land, a mythic 0.75). **Go up, not down, when lands are also spells:** a
  cycling deck wants **~39**, run liberally on MDFCs and cycling lands, because a land that
  cycles is never a flooded draw. Same for landcycling: basic landcycling on something like
  Ash Barrens is still cycling, so it triggers every cycling payoff *and* fetches a land.
  Don't argue the count down on "flood turns into cards" grounds; that reasoning is what makes
  the extra lands correct in the first place.
- **8–10 ramp pieces**, chosen by the curve rule above. More (up to ~20) for expensive
  central commanders and draw-heavy decks; fewer for low curves.
- **10+ real card advantage** sources that net 2+ cards. Cantrips don't count. Engines beat
  one-shots only if they pay back before the game ends.
- **8–14 interaction** pieces, mostly at 1–2 mana, scaled to how slowly the deck wins, plus
  **3–5 wipes** for slower decks (at least one for artifacts and enchantments). Answers must
  cover every permanent type, include one graveyard hate piece, and own an out to indestructible.
- the remainder on the theme and its payoffs

Ask about budget and bracket if they weren't stated. Both massively change the answer.
