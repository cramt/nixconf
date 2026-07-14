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
just update           # Update flake inputs, gems, npins, and packages (run daily by CI's update.yml,
                      # which maintains an `update` branch PR prebuilt into cachix — merge it to update)
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

The flake uses `flake-parts`. `flake.nix` is a minimal wrapper around `flake-parts.lib.mkFlake` whose entire module list is `inputs.import-tree ./modules` — **every `.nix` file under `modules/` is auto-imported as a flake-parts module**. There is no central import list; dropping a file into `modules/` is enough to wire it in.

The flake-parts plumbing lives in `modules/flake/`:

| File | Purpose |
|------|---------|
| `modules/flake/lib.nix` | Instantiates `myLib` and exposes it as `_module.args.myLib` to all flake modules |
| `modules/flake/hosts.nix` | Declares the `nixosHosts` option (hostname → `{ config; nixpkgs; }`) and builds `flake.nixosConfigurations` via `myLib.mkSystem` |
| `modules/flake/systems.nix` | The `systems` list for `perSystem` |
| `modules/flake/packages.nix` | `perSystem` packages (e.g. `eros-img`, `titan-img`) |
| `modules/flake/hm-modules.nix` | Typed accumulator options (`hmModules.default/features/bundles`) wired into `flake.homeManagerModules` once, to avoid freeform merge conflicts |

The flake defines NixOS systems for hosts: `saturn`, `mars`, `luna`, `eros`, `ganymede`. Each is registered in the `nixosHosts` attrset in `modules/flake/hosts.nix`. **To add a new host, add one line to `nixosHosts`** (set `nixpkgs` per-host to use a vendor cache, as `eros` does with `nixpkgs-rpi`).

### myLib (`myLib/default.nix`)

A thin helper exposing `mkSystem { config, nixpkgs ? inputs.nixpkgs }`, which calls `nixpkgs.lib.nixosSystem` and imports `outputs.nixosModules.default`, opnix, and every other `outputs.nixosModules.*` entry.

### Module System Pattern

There is **no automatic enable-option wrapping**. Each module file is a flake-parts module that *manually* registers itself into the appropriate output and declares its own `enable` option guarded by `lib.mkIf`. The directory a file lives in is organizational; the namespace it lands in is whatever the file declares.

**NixOS modules** — a file sets `flake.nixosModules."<category>.<name>"` and declares `options.myNixOS.<...>`:

```nix
{ ... }: {
  flake.nixosModules."services.foo" = { config, lib, ... }: let
    cfg = config.myNixOS.services.foo;
  in {
    options.myNixOS.services.foo.enable = lib.mkEnableOption "myNixOS.services.foo";
    config = lib.mkIf cfg.enable { /* ... */ };
  };
}
```

Conventionally: `services/*.nix` → `myNixOS.services.<name>`, `bundles/*.nix` → `myNixOS.bundles.<name>`, and `features`/`hardware`/`networking`/`security`/`virtualization`/`desktop` files → `myNixOS.<name>`. `modules/base/` files (`nixos-default.nix`, `portselector.nix`) are unconditional base config / `nixosModules.default`.

**Home Manager modules** — a file contributes to the typed accumulators from `hm-modules.nix` and declares `options.myHomeManager.<...>`:
- `modules/hm-base/*` → `hmModules.default` (always imported)
- `modules/hm-features/<name>.nix` → `hmModules.features.<name>` → `myHomeManager.<name>.enable`
- `modules/hm-bundles/<name>.nix` → `hmModules.bundles.<name>` → `myHomeManager.bundles.<name>.enable`

### Host Structure

Each host in `hosts/<name>/` has:
- `configuration.nix` — top-level NixOS config; enables `myNixOS.*` options and sets `home-users`
- `home.nix` — Home Manager config for the user; enables `myHomeManager.*` options
- `hardware-configuration.nix` — auto-generated hardware config
- `monitors.nix` — monitor layout (used for kernel `video=` params and wayland config)
- `ssh.pub.nix` — host SSH public key

### Key Subsystems

- **Theming**: `stylix` (dark theme, Iosevka Nerd Font). Configured in `modules/bundles/nixos-general.nix`. The `stylixAsset` option accepts an image or `.mp4` (first frame is extracted).
- **Secrets**: `opnix` (1Password-based). Enabled per-host with `myNixOS.opnix-secrets.enable = true`.
- **Port assignment**: `modules/base/portselector.nix` provides a `port-selector` NixOS option that deterministically assigns ports to services by hashing their names, with manual overrides via `set-ports`.
- **Non-flake pins**: `npins/` for sources that don't have flake support.
- **Gems**: `gems/` — Ruby gems used by scripts (locked with `bundle lock`).
- **Packages**: `packages/` — custom packages (`declaradroid`, `cockatrice`, `steamlink`, `zed-bin`).
- **Scripts**: `scripts/` — Nix-defined scripts (`zellij_smart_start`, `sway_gaming`, `keep_awake`, etc.).

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

## Machine & Host Facts

- `saturn` — Alex's desktop (COSMIC daily driver, niri secondary). Home machine; work happens on a separate laptop.
- `luna` — home server, 192.168.178.24. `ganymede` — 192.168.178.47. `eros` — 2GB RPi4 TV kiosk. `titan` — OpenWrt router.
- Daily browser is Zen. Firefox, Thunderbird, and Heroic are installed but unused.
- `/external_storage` is a mergerfs pool over slow HDDs — no heavy IO through the mergerfs mount.

## Build Policy

- Small config changes build locally on saturn. Chunky/uncached/aarch64 builds go through GitHub Actions (ARM runner) + cachix.
- NEVER build or eval on eros (2GB RAM, hard-crashes). Build on saturn and deploy with `nh os switch --target-host`.
- If Alex is gaming: `--cores 1`, run in background.
- Flakes only see git-tracked files — `git add` new files before `nix build`.
- "CI is failing" unqualified = the saturn build.

## Deploy Workflow

- Alex runs `nh os switch` herself (wl-copy it when ready). After she deploys, verify: ssh in, `systemctl --failed`, journalctl on the touched services.
- `hermes-agent`'s container doesn't recreate on config change — `systemctl restart hermes-agent` manually.
- Editing a 1Password secret in place requires restarting `opnix-secrets`, not just the consuming service.
- Secrets go through opnix (`/etc/opnix-token`) — never interactive `op` prompts.
