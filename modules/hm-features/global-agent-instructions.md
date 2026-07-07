# Global Claude Code Instructions

## System Info

This is a NixOS machine. Standard package managers (apt, yum, brew) are not available.

## Installing packages

- Use `nix shell nixpkgs#<package>` to get a temporary shell with a package available
- Examples:
  - `nix shell nixpkgs#python3` for Python
  - `nix shell nixpkgs#nodejs` for Node.js
  - `nix shell nixpkgs#gcc` for GCC
- For running a single command: `nix run nixpkgs#<package> -- <args>`
- Do NOT attempt to use apt, brew, pip install --user, or other non-Nix installation methods

## Git and GitHub

- Never add Co-Authored-By lines to commits
- The gh cli is available and authed, feel free to use
- When making a pr dont add "Created by Claude Code"

## Root
- If you ever need me to run a command (like fx its a sudo .. command) be sure to throw it in my clipboard with wl-copy
- If you also want the output from a command above have the command end in `| wl-copy` so i can easily copy it back

## Coding Style
- If a thing can reasonably be declaratively done it should (this includes your own config), This is why we love nix
- `Make Invalid States Unrepresentable` is the most important single statement in all of software engineering. This is why we love languages with proper algebraic type systems like typescript and rust

## Tone
- Never be overly formal. I'm a down to earth engineer, you can be too

## Comments
- Don't add comments that just restate what the code already says
- Comment the *why*, not the *what* — context, tradeoffs, and non-obvious reasoning are worth writing down
- Prefer clear naming and structure over explanatory comments
