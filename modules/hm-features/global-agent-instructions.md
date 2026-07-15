# Global Claude Code Instructions

## System Info

This is a NixOS machine. No apt/yum/brew — everything goes through nix.

## Installing packages

- Temporary shell: `nix shell nixpkgs#<package>`; single command: `nix run nixpkgs#<package> -- <args>`
- If the repo has a flake.nix, run build/test commands through `nix develop --command <cmd>`

## Git and GitHub

- Never add AI attribution anywhere — no Co-Authored-By, no "Generated with Claude Code" footers, in commits, PRs, or comments
- The gh cli is available and authed
- Remotes are always SSH, never HTTPS
- My personal repos: when work is green, commit and push to the default branch without asking. No feature branches or PRs unless I ask
- PRs: `gh pr create --web`

## Bias to action

- Don't end turns with option menus — pick the sensible next step, do it, say what you did
- Ask only before destructive/irreversible actions or real design forks
- Offhand remarks aren't mandates — confirm blast radius before repo-wide sweeps

## Manual steps

- Anything I must run/paste myself (sudo, auth flows, other apps): wl-copy it, don't just print it
- If you want the output back, end the command with `| wl-copy`

## Delegating to cheap models

- A custom model `gpt-5.5-think-deeper` (M365-proxied GPT-5.5, shown in `/model` as "GPT-5.5 Deep Research (M365)") is routed through the claude-splitter. It is very cheap.
- Reach for it in workflows and subagents via the `model` override — `agent(prompt, { model: 'gpt-5.5-think-deeper' })` — and lean on it often to keep spend down.
- It's great at taste-free work: mechanical implementation, bulk edits, and following exact commands to the letter. Keep design, judgement calls, and anything that needs taste on Claude.

## Coding Style

- If a thing can reasonably be declaratively done it should (this includes your own config), This is why we love nix
- A runtime fix is never the deliverable — pair it with the declarative nixconf change
- `Make Invalid States Unrepresentable` is the most important single statement in all of software engineering. This is why we love languages with proper algebraic type systems like typescript and rust
- Rust for native executables, TypeScript for HTTP backends. Never Go
- Every pin/workaround gets a comment with the upstream issue link and removal condition
- Empirical tuning (prompts, perf, flakiness): several distinct hypotheses, measure on a repeatable bench, conclude from data
- If a change moves a tracked number or status, update README/docs in the same commit

## Verification

- "Should work" isn't done — observe it working before claiming it
- Long-running ops: report actual throughput and whether waiting is worth it

## Tone

- Never be overly formal. I'm a down to earth engineer, you can be too

## Comments

- Comment the *why*, not the *what* — prefer clear naming and structure over explanatory comments
