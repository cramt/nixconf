# nixconf

My personal NixOS configuration, managing a fleet of machines using [flake-parts](https://github.com/hercules-ci/flake-parts), [Home Manager](https://github.com/nix-community/home-manager), and a custom module system.

## Hosts

| Host | Type | Description |
|------|------|-------------|
| `saturn` | Desktop | AMD gaming PC with Wayland/COSMIC, Secure Boot (lanzaboote), Ollama (ROCm) |
| `luna` | Server | Home server with NAS, Ollama (CUDA), game servers, Caddy, Nix binary cache |
| `mars` | Desktop | Secondary desktop, AMD gaming PC with COSMIC |
| `ganymede` | Laptop | NVIDIA laptop running KDE Plasma 6, always-on (lid-close ignored) |
| `eros` | SBC | Raspberry Pi (aarch64), SD card image |

## Common Commands

```bash
# Deploy the fleet: builds and activates on every host answering right now,
# skipping the ones that are powered off. Runs from any host, and the machine
# you run it on is just another target.
just deploy
just deploy luna ganymede   # ...or narrow it to named hosts

# Apply config to the current host only, without the network
nh os switch

just update           # Update flake inputs, gems, npins, and packages (CI runs this weekly — see below)
just update_flake     # Update flake.lock only
just update_gems      # Update Ruby gem lockfile

# Infrastructure (uses 1Password for secrets)
just tf <args>        # Run OpenTofu in ./infra with env vars from opnix

# Flake management
nix flake update
npins update          # Update non-flake pinned sources
```

## Updating

A daily GitHub Actions workflow (`update.yml`) runs `just update`, force-pushes the
result to the `update` branch, keeps a single open PR against `main`, and triggers
the build workflow on that branch so every package and host toplevel lands in cachix.
To update a machine: merge the PR when it's green, then `nh os switch` — everything
substitutes from the cache.

## Architecture

### Flake Structure

`flake.nix` is a thin wrapper around `flake-parts.lib.mkFlake` that imports modules from `modules/`:

| Path | Purpose |
|------|---------|
| `modules/flake/lib.nix` | Instantiates `myLib` and exposes it as `_module.args.myLib` |
| `modules/flake/hosts.nix` | Discovers hosts from `hosts/` and builds `nixosConfigurations` |
| `modules/flake/deploy.nix` | Derives the deploy-rs node set from those hosts |
| `modules/flake/packages.nix` | Per-system packages (e.g. `eros-img`) |
| `modules/flake/hm-modules.nix` | Typed accumulators for the Home Manager module outputs |

### Module System

Both `nixosModules/` and `homeManagerModules/` use `extendModules` to auto-generate enable options for every file in their subdirectories.

**NixOS modules** (accessed as `myNixOS.*` in host configs):
- `nixosModules/features/<name>.nix` → `myNixOS.<name>.enable = true`
- `nixosModules/bundles/<name>.nix` → `myNixOS.bundles.<name>.enable = true`
- `nixosModules/services/<name>.nix` → `myNixOS.services.<name>.enable = true`

**Home Manager modules** (accessed as `myHomeManager.*` in home configs):
- `homeManagerModules/features/<name>.nix` → `myHomeManager.<name>.enable = true`
- `homeManagerModules/bundles/<name>.nix` → `myHomeManager.bundles.<name>.enable = true`
- `homeManagerModules/fixes/` — unconditional fixes, always imported

### Adding a New Host

Create `hosts/<name>/` — that's it. `modules/flake/hosts.nix` reads `hosts/`, so a
directory there becomes a `nixosConfigurations.<name>` and a `just deploy` target with
no list to edit. Everything is derived from the folder name:

| | derived as |
|---|---|
| entrypoint | `hosts/<name>/configuration.nix` |
| `networking.hostName` | `<name>` (`mkDefault`, so a host can override) |
| user's Home Manager config | `hosts/<name>/home.nix`, if present |
| SSH keys (user + root) | `myLib/keys.nix` |
| deploy address | `<name>`, resolved over LAN DNS |

Add `hosts/<name>/host.nix` only to deviate — it takes `nixpkgs` (build from a vendor
cache, as `eros` does) and `address` (if DNS can't find the host). See
`hosts/eros/host.nix`.

### Key Subsystems

| Subsystem | Description |
|-----------|-------------|
| **Theming** | [stylix](https://github.com/nix-community/stylix) — dark theme with Iosevka Nerd Font. `stylixAsset` accepts an image or `.mp4` |
| **Secrets** | [opnix](https://github.com/brizzbuzz/opnix) — 1Password-based secret injection |
| **Port assignment** | `portselector.nix` — deterministically assigns ports by hashing service names |
| **Binary cache** | [harmonia](https://github.com/nix-community/harmonia) on `luna` — serves the local Nix store |
| **Non-flake pins** | `npins/` — for sources without flake support |
| **Gems** | `gems/` — Ruby gems used by scripts, locked with `bundle lock` |
| **Packages** | `packages/` — custom packages |

### Home Manager Bundles

| Bundle | Purpose |
|--------|---------|
| `general` | Core user tools |
| `graphical` | Wayland/desktop apps |
| `development` | Dev toolchain (Go, Rust, Node, Ruby, Java, Zig, etc.) |
| `gaming` | Steam and game-related tools |
| `work` | Work-specific config |

## Infrastructure

Terraform/OpenTofu configs live in `infra/`. Credentials are injected from 1Password via `opnix`.

```bash
just tf plan
just tf apply
```
