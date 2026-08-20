# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Deploy the fleet (deploy-rs): builds and activates on every host answering on
# the network right now, skipping powered-off ones. Runs from any host; the
# machine you run it on is just another target.
just deploy
just deploy luna ganymede   # ...or narrow to named hosts

# Apply system config to the current host only, no network
nh os switch

# Shortcut recipes (via just)
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
| `modules/flake/hosts.nix` | Discovers hosts by reading `hosts/`, declares the `nixosHosts` option (hostname → `{ config; nixpkgs; address; }`) and builds `flake.nixosConfigurations` via `myLib.mkSystem` |
| `modules/flake/deploy.nix` | Derives `flake.deploy` (deploy-rs nodes) from `nixosHosts`; driven by `just deploy` |
| `modules/flake/systems.nix` | The `systems` list for `perSystem` |
| `modules/flake/packages.nix` | `perSystem` packages (e.g. `eros-img`, `flash-eros`) |
| `modules/flake/hm-modules.nix` | Typed accumulator options (`hmModules.default/features/bundles`) wired into `flake.homeManagerModules` once, to avoid freeform merge conflicts |

The flake defines NixOS systems for hosts: `saturn`, `mars`, `luna`, `eros`, `ganymede`. There is no host list — `modules/flake/hosts.nix` reads `hosts/`, so **every directory under `hosts/` is a NixOS host and a `just deploy` target**. To add one, create the folder. Everything else is derived from its name: the entrypoint (`configuration.nix`), `networking.hostName`, the user's `home.nix`, and the deploy address.

A host only needs `hosts/<name>/host.nix` when it deviates from that; it takes `nixpkgs` (build from a vendor cache, as `eros` does with `nixpkgs-rpi`) and `address` (when DNS can't resolve the bare hostname).

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
- `configuration.nix` — top-level NixOS config; enables `myNixOS.*` options
- `home.nix` — Home Manager config for the user; enables `myHomeManager.*` options. Picked up automatically as `home-users.cramt.userConfig`
- `hardware-configuration.nix` — auto-generated hardware config
- `host.nix` — *optional* flake-level knobs (`nixpkgs`, `address`); only `eros` has one
- `monitors.nix` — monitor layout (used for kernel `video=` params and wayland config)
- `ssh.pub.nix` — host SSH public key

SSH keys are not per-host: `myLib/keys.nix` is the single source, defaulted into
`home-users.*.authorizedKeys` (which is also where root's keys come from, and therefore
what makes `just deploy` able to reach a host at all).

### Key Subsystems

- **Theming**: `stylix` (dark theme, Iosevka Nerd Font). Configured in `modules/bundles/nixos-general.nix`. The `stylixAsset` option accepts an image or `.mp4` (first frame is extracted).
- **Secrets**: `opnix` (1Password-based). Enabled per-host with `myNixOS.opnix-secrets.enable = true`.
- **Port assignment**: `modules/base/portselector.nix` provides a `port-selector` NixOS option that deterministically assigns ports to services by hashing their names, with manual overrides via `set-ports`.
- **Non-flake pins**: `npins/` for sources that don't have flake support.
- **Gems**: `gems/` — Ruby gems used by scripts (locked with `bundle lock`).
- **Packages**: `packages/` — custom packages (`agent-browser`, `agentsview`, `cockatrice`, `colibri`, `declaradroid`, `saturn-windows-image`, `steamlink`, `t3code`).
- **Zed extensions**: `packages/mkZedExtension.nix` builds an extension into Zed's `installed/<id>` layout (wasm32-wasip2 via fenix, tree-sitter parsers via `pkgsCross.wasi32`) so `modules/hm-features/zed.nix` can symlink it in. This is the only declarative route for extensions that aren't in Zed's registry — registry ones just go in the `extensions` list. Grammar sources are npins pins, cross-checked at build time against the revision the extension's own `extension.toml` declares.
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
- `luna` — home server, 192.168.178.24. `ganymede` — 192.168.178.47. `eros` — 2GB RPi4 TV kiosk. `mars` — secondary desktop.
- Fleet hostnames resolve over the router's DNS, so `just deploy` addresses hosts by name, not IP.
- Daily browser is Zen. Firefox, Thunderbird, and Heroic are installed but unused.
- `/external_storage` is a mergerfs pool over slow HDDs — no heavy IO through the mergerfs mount.
- saturn's `/llm/primary` (400G, 970 EVO) and `/llm/mirror` (200G, 980) are plain ext4 *outside* the btrfs pool, for colibrì expert streaming. Deliberately not on the pool: `compress=zstd:1` kills O_DIRECT, and the engine's dual-drive read splitting needs two separate filesystems. See `docs/saturn-llm-storage.md`.

## Build Policy

- Small config changes build locally on saturn. Chunky/uncached/aarch64 builds go through GitHub Actions (ARM runner) + cachix.
- NEVER build or eval on eros (2GB RAM, hard-crashes). `just deploy` already builds everything locally and only copies closures out (`remoteBuild = false`), so this holds by construction.
- If Alex is gaming: `--cores 1`, run in background.
- Flakes only see git-tracked files — `git add` new files before `nix build`.
- "CI is failing" unqualified = the saturn build.

## Deploy Workflow

- Alex runs the deploy herself (wl-copy it when ready) — `just deploy` for the fleet, `nh os switch` for the local host alone. After she deploys, verify: ssh in, `systemctl --failed`, journalctl on the touched services.
- deploy-rs activates with magic rollback: a host that loses its network mid-activation reverts itself. A deploy that "hung then rolled back" means the new config broke connectivity, not that deploy-rs failed.
- `hermes-agent`'s container doesn't recreate on config change — `systemctl restart hermes-agent` manually.
- Editing a 1Password secret in place requires restarting `opnix-secrets`, not just the consuming service.
- Secrets go through opnix (`/etc/opnix-token`) — never interactive `op` prompts.
