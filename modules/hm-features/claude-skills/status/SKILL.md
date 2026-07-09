---
name: status
description: Use when Alex asks where a project stands — "whats the status", "how far are we", "where are we on this project", "whats next before 1.0", or asks for an architectural review. Report real state from roadmap + git + tests, rank next steps, then start on the top one.
---

# status

The session-opener: figure out where the project actually is, then get moving.

## Procedure

1. **Read the ledgers**: planning docs (ROADMAP*, TODO*, *checklist*, docs/future-work and friends), README status counters, and `git log --oneline -20` since they were last touched.
2. **Check reality, don't trust the docs**: run the test/lint suite through the devshell (`nix develop --command <cmd>`) if it's quick, or pull CI status via `gh`. Stale ledgers lie; note any drift between docs and reality (and fix the docs as you go).
3. **Report**: what's done since last session, what's in flight, what's blocked, and a short ranked list of next levers — highest impact first, with a one-line why per item.
4. For **architectural review** variants ("whats good whats bad"), fan out one subagent per package/subsystem in parallel and synthesize.
5. **Don't stop at a menu.** State which item you're taking and start working it. Alex will redirect if she wants a different one.
