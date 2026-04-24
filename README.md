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
# Apply config to current host
nh os switch

# Deploy to a remote host
nh os switch --target-host root@<ip> -H <hostname>

# Shortcuts
just build_luna       # Deploy to luna (192.168.178.24)
just build_ganymede   # Deploy to ganymede (192.168.178.47)
just update           # Update fwupd, flake inputs, gems, npins, and rebuild
just update_flake     # Update flake.lock only
just update_gems      # Update Ruby gem lockfile

# Infrastructure (uses 1Password for secrets)
just tf <args>        # Run OpenTofu in ./infra with env vars from opnix

# Flake management
nix flake update
npins update          # Update non-flake pinned sources
```

## Architecture

### Flake Structure

`flake.nix` is a thin wrapper around `flake-parts.lib.mkFlake` that imports modules from `modules/`:

| Path | Purpose |
|------|---------|
| `modules/lib.nix` | Instantiates `myLib` and exposes it as `_module.args.myLib` |
| `modules/hosts.nix` | Declares `nixosHosts` option and builds `nixosConfigurations` |
| `modules/packages.nix` | Per-system packages (e.g. `eros-img`) |
| `modules/exported-modules.nix` | Exports `nixosModules.default` and `homeManagerModules.default` |

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

Add one line to `nixosHosts` in `modules/hosts.nix`:

```nix
nixosHosts."myhostname" = myLib.mkSystem ./hosts/myhostname/configuration.nix;
```

Then create `hosts/myhostname/configuration.nix` (and `home.nix`, `hardware-configuration.nix` as needed).

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
