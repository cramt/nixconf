# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Apply system config to current host
nh os switch

# Deploy to a remote host
nh os switch --target-host root@<ip> -H <hostname>

# Shortcut recipes (via just)
just build_luna       # Deploy to luna (192.168.178.24)
just build_ganymede   # Deploy to ganymede (192.168.178.47)
just update           # Update fwupd, flake inputs, gems, npins, and rebuild
just update_flake     # Update flake.lock only
just update_gems      # Update Ruby gem lockfile

# Infrastructure (uses 1Password for secrets)
just tf <args>        # Run terraform in ./infra with env vars from opnix

# Flake management
nix flake update
npins update          # Update non-flake pinned sources
```

## Architecture

### Flake Structure

The flake uses `flake-parts` (replacing the old `flake-utils`). `flake.nix` is a minimal wrapper around `flake-parts.lib.mkFlake` that imports four modules from `flake/`:

| File | Purpose |
|------|---------|
| `flake/lib.nix` | Instantiates `myLib` and exposes it as `_module.args.myLib` to all flake modules |
| `flake/hosts.nix` | Declares the `nixosHosts` option (attrset of hostname → config path) and builds `nixosConfigurations` |
| `flake/packages.nix` | `perSystem` packages (e.g. `eros-img`) — replaces `flake-utils.lib.eachDefaultSystem` |
| `flake/exported-modules.nix` | Exports `nixosModules.default` and `homeManagerModules.default` as flake outputs |

The flake defines NixOS systems for hosts: `saturn`, `mars`, `luna`, `eros`, `ganymede`. Each host is registered in `flake/hosts.nix` under the `nixosHosts` option and built via `myLib.mkSystem ./hosts/<name>/configuration.nix`. **To add a new host, add one line to `nixosHosts` in `flake/hosts.nix`.**

### myLib (`myLib/default.nix`)

A helper library providing:
- `mkSystem` / `mkHome` — build NixOS/Home Manager configurations
- `extendModules` — the core pattern: takes a directory of modules and automatically wraps each in an enable option
- `filesIn` / `dirsIn` — directory enumeration helpers

### Module System Pattern

Both `nixosModules/` and `homeManagerModules/` use `extendModules` to auto-generate enable options for every file in `features/`, `bundles/`, and `services/` subdirectories.

**NixOS modules** (accessed as `myNixOS.*` in host configs):
- `nixosModules/features/<name>.nix` → `myNixOS.<name>.enable = true`
- `nixosModules/bundles/<name>.nix` → `myNixOS.bundles.<name>.enable = true`
- `nixosModules/services/<name>.nix` → `myNixOS.services.<name>.enable = true`

**Home Manager modules** (accessed as `myHomeManager.*` in home configs):
- `homeManagerModules/features/<name>.nix` → `myHomeManager.<name>.enable = true`
- `homeManagerModules/bundles/<name>.nix` → `myHomeManager.bundles.<name>.enable = true`

`homeManagerModules/fixes/` contains unconditional fixes (no enable option; always imported).

### Host Structure

Each host in `hosts/<name>/` has:
- `configuration.nix` — top-level NixOS config; enables `myNixOS.*` options and sets `home-users`
- `home.nix` — Home Manager config for the user; enables `myHomeManager.*` options
- `hardware-configuration.nix` — auto-generated hardware config
- `monitors.nix` — monitor layout (used for kernel `video=` params and wayland config)
- `ssh.pub.nix` — host SSH public key

### Key Subsystems

- **Theming**: `stylix` (dark theme, Iosevka Nerd Font). Configured in `nixosModules/bundles/general.nix`. The `stylixAsset` option accepts an image or `.mp4` (first frame is extracted).
- **Secrets**: `opnix` (1Password-based). Enabled per-host with `myNixOS.opnix-secrets.enable = true`.
- **Port assignment**: `portselector.nix` provides a `port-selector` NixOS option that deterministically assigns ports to services by hashing their names, with manual overrides via `set-ports`.
- **Non-flake pins**: `npins/` for sources that don't have flake support.
- **Gems**: `gems/` — Ruby gems used by scripts (locked with `bundle lock`).
- **Packages**: `packages/` — custom packages (`declaradroid`, `codexbar`).
- **Scripts**: `scripts/` — Nix-defined scripts (zellij, sway gaming, etc.).

### Home Manager Bundles

| Bundle | Purpose |
|--------|---------|
| `general` | Core user tools |
| `graphical` | Wayland/desktop apps |
| `development` | Dev toolchain (Go, Rust, Node, Ruby, Java, Zig, etc.) |
| `gaming` | Steam, game-related tools |
| `work` | Work-specific config |

### Infrastructure

Terraform configs live in `infra/`. Use `just tf <args>` which injects credentials from 1Password via `opnix`.
