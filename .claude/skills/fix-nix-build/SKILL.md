---
name: fix-nix-build
description: Use when a nix build is failing — after `just update` / flake update, in CI, or on rebuild ("i did an update and its failing", "build is broken", "CI is red"). Triage the failing derivation, find the upstream issue, apply a commented workaround, verify with a build — never switch.
---

# fix-nix-build

The recurring post-update breakage workflow.

## Ground rules

- Respect the Build Policy in AGENTS.md: small stuff builds locally on saturn, chunky/aarch64 goes through CI + cachix, NEVER build or eval on eros, `--cores 1` if Alex is gaming.
- Build only. Never `nh os switch` or activate anything — Alex switches herself. When the fix is ready, wl-copy the switch command.
- "CI is failing" unqualified = the saturn toplevel.
- Flakes only see git-tracked files — `git add` new files before building.

## Procedure

1. **Reproduce cheaply.** For eval errors, `nix eval` the failing attribute first — much faster than a build. Otherwise build the toplevel in the background and watch the log:
   `nix build .#nixosConfigurations.saturn.config.system.build.toplevel --no-link`
2. **Isolate the failing derivation** from the log — the actual package that failed, not the toplevel that depends on it.
3. **Check upstream before hand-rolling anything.** Search nixpkgs issues/PRs and the package's own repo for the error message. Post-update breakage is almost always already reported, often with a fix in flight.
4. **Fix, in preference order:**
   - pin/roll back the offending flake input or use the fixed PR's commit
   - overlay/override (patch, version pin, disabled test)
   - config escape hatch (`permittedInsecurePackages`, feature toggle)
   - disable the affected module and say so
5. **Comment every workaround** with the upstream issue link and the condition for removing it — a note to future sessions.
6. **Verify with a rebuild**, then report: what broke, root cause, the fix, and when it can be unwound. wl-copy `nh os switch` if it's ready to apply.
