# Vendored pstack skills

Ten always-on skills lifted from [cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack)
(pstack, by Lauren Tan / poteto), MIT licensed — see `LICENSE`.

Vendored rather than pinned because the upstream set is one tree rooted at
`poteto-mode`, and only these ten stand alone: each one's `Apply when…` scope is
either "any non-trivial work" or "any code task", so they carry no dependency on
the dispatcher or on the other twenty-odd `principle-*` leaves.

Three deltas from upstream, all deliberate:

1. **`principle-` prefix dropped**, directory name and frontmatter `name:` kept in
   sync — Claude Code keys skills off the directory.
2. **`disable-model-invocation: true` stripped.** Upstream ships every principle
   slash-command-only, so they can only fire when `poteto-mode` routes to them.
   Without the dispatcher that makes them inert, which defeats the point of
   picking the universally-applicable ones.
3. **Cross-references to unvendored siblings inlined.** `type-system-discipline`
   pointed at `boundary-discipline` and `encode-lessons-in-structure`;
   `sequence-verifiable-units` pointed at `prove-it-works`. Each was a trailing
   "see the X skill" clause on a sentence that already stated the rule, so the
   rule stays and the dangling pointer is gone.

Re-vendoring after an upstream change means redoing all three by hand. They're
small and the skills change rarely; if that stops being true, script it.

`unslop` is the strictest of the set and applies to everything written, including
commit messages: no em dashes (and no parentheses as a substitute), sentence-case
headings, no decorative emoji.
