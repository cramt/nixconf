# Saturn → disko two-SSD btrfs pool migration

Converts saturn's two 1TB M.2 NVMe SSDs from the old split layout to a single
disko-managed btrfs pool, and reserves a 150G slot for a fresh Windows install.

**This is a full reinstall, not a live rebuild** — disko repartitions and
**wipes both SSDs**, so it can't run against saturn's own mounted root. Primary
method: **nixos-anywhere** driven from another machine (kexecs saturn into a RAM
installer, then wipes + installs); fallback: a local USB install. Either way the
three SATA HDDs (`/mnt/amirani`, `/mnt/titan`, `/mnt/phoebe` → mergerfs
`/external_storage`) are **not touched** — they stage the backup.

## Target layout

| Device | Old | New |
|--------|-----|-----|
| nvme0n1 (Samsung 980) | `/boot` (512M) + `/` ext4 | `1G ESP (/boot)` + btrfs member |
| nvme1n1 (Samsung 970 EVO) | `/nix` ext4 + Windows NTFS | btrfs member + `150G NTFS` (Windows) |

Result: one btrfs filesystem `nvme-pool`, `-d single -m raid1`, subvolumes
`@root → /`, `@nix → /nix`, `@home → /home`, ~1.7TB usable shared across all
three. Windows dual-boots off the shared ESP on nvme0n1.

Defined in `hosts/saturn/disko.nix`; wired via `hosts/saturn/configuration.nix`
(imports `inputs.disko.nixosModules.default` + `./disko.nix`).
`hardware-configuration.nix` no longer declares `/`, `/nix`, `/boot` (disko owns
them) but keeps the HDD mounts.

## 0. Pre-flight — back up ONLY the auth-critical state

Everything on the SSDs is destroyed, but almost none of it needs backup: the nix
store, games, `~/code`, HM dotfiles and nixarr media all re-fetch over the
network, which is faster than these HDDs. Carry **only** the bits that would
otherwise cost a re-authentication:

| What | Path | Size | Why |
|------|------|------|-----|
| Zen profile | `~/.config/zen/` | ~600M | bookmarks, saved logins (`key4.db`+`logins.db`), website sessions (`cookies.sqlite`+`storage/`) |
| 1Password desktop | `~/.config/1Password/` | ~35M | keeps the account registered (skip re-adding via Secret Key) |
| GPG private keys | `~/.gnupg/` | 128K | `private-keys-v1.d` — **cannot be regenerated** |
| Matrix/Element | `~/.config/Element/` | 43M | session + E2E device keys (else re-verify, risk losing encrypted history) |
| Claude Code | `~/.claude/` + `~/.claude.json` | 118M | oauth token + auto-memory + session history |
| GitHub CLI | `~/.config/gh/` | 12K | oauth token |
| Copilot | `~/.config/github-copilot/` | 12K | auth token |
| crates.io | `~/.cargo/credentials.toml` | 4K | publish token |
| Steam login | `~/.local/share/Steam/config/{loginusers,config}.vdf` | small | skip Steam Guard re-auth (NOT `steamapps`/`htmlcache`) |
| opnix token | `/etc/opnix-token` | 817B | bootstrap service-account token; opnix can't fetch its own token |
| Wi-Fi (if any) | `/etc/NetworkManager/system-connections/` | small | saved Wi-Fi PSKs (skip if saturn is ethernet-only) |

**SSH:** nothing to carry — keys come from the 1Password agent
(`IdentityAgent ~/.1password/agent.sock`) and `~/.ssh/config` is a HM symlink.

Deliberately **skipped** (re-fetched/regenerated, not backed up): nix store,
`~/code/*` (re-clone), Steam `steamapps` + `htmlcache`, Heroic/Bottles game data
(`~/.var/app/*`, ~6.5G), `/var/lib/nixarr-test` media, docker, **waydroid**,
Tailscale state (auto re-auths via the opnix preauth key).

> Two honesty caveats: the 1Password *local vault* is encrypted with keys tied
> to your account login, so you may still enter your account password once on
> first unlock — restoring the dir only skips re-registering the account. Zen
> logins survive only if no Firefox *primary password* is set (it isn't here).

## 1. Back up the auth set to a HDD

Back up to a **raw** HDD (`/mnt/amirani`), not the mergerfs union — the installer
can mount the raw disk by-uuid but not the mergerfs. `rsync -R` preserves each
path relative to `$HOME` so restore is a clean reverse copy.

```bash
B=/mnt/amirani/saturn-migration-backup
mkdir -p "$B/home"

# --- user auth state (run as your user) ---
for p in \
  .config/zen \
  .config/1Password \
  .gnupg \
  .config/Element \
  .claude .claude.json \
  .config/gh \
  .config/github-copilot \
  .cargo/credentials.toml \
; do
  [ -e "$HOME/$p" ] && rsync -aHAR --info=progress2 "$HOME/./$p" "$B/home/"
done
# Steam login only (never steamapps / htmlcache):
rsync -aHAR "$HOME/./.local/share/Steam/config/loginusers.vdf" \
            "$HOME/./.local/share/Steam/config/config.vdf" "$B/home/"

# --- system auth state (root) ---
sudo cp -a /etc/opnix-token "$B/opnix-token"
# saved Wi-Fi PSKs — skip if saturn is ethernet-only:
sudo rsync -aHA /etc/NetworkManager/system-connections/ "$B/nm-connections/" 2>/dev/null || true
sync
```

And make sure the flake is on the remote (so the fresh box can build itself):

```bash
cd ~/nixconf && git status && git log --oneline -1 && git push
```

## 2. Deploy with nixos-anywhere (from another machine)

nixos-anywhere SSHes into saturn, **kexecs it into a RAM-only NixOS installer**
(so the running root unmounts and both NVMe become wipeable), then runs disko
(destroy + format + mount) and `nixos-install` from this flake — one command.
The three SATA HDDs and the step-1 backup on `/mnt/amirani` are **not touched**
(disko only names the two NVMe by-id devices).

**Prerequisites:**

- **SSH must be live on the *current* saturn.** saturn's config gains
  `myNixOS.services.sshd.enable = true` + your `authorizedKeys` (same block as
  luna/ganymede). Enable it on `main` and `nh os switch` **before** running this,
  so the running ext4 system is reachable. (nixos-anywhere connects to the real
  saturn first, then kexecs it.)
- **A controller machine** (mars / a laptop) with: this flake checked out on
  `saturn-disko`, the 1Password SSH agent loaded (it holds the authorized key),
  and LAN reach to saturn.
- **The step-1 backup is already on `/mnt/amirani`.** Do it while saturn is still
  in its normal OS — the SSD-resident `~/.config/*` is gone after the wipe.

**Run from the controller:**

```bash
cd nixconf && git checkout saturn-disko && git pull
nix run github:nix-community/nixos-anywhere -- \
  --flake .#saturn \
  --target-host root@<saturn-ip>
```

`root@saturn` works because root inherits every home-user's `authorizedKeys`
(`modules/bundles/nixos-users.nix:71`). Prefer a normal login? Use
`--sudo --target-host cramt@<saturn-ip>`.

Optional — provision the opnix token on the *very first* boot instead of after:
put the token at `./extra/etc/opnix-token` on the controller and add
`--extra-files ./extra`. Otherwise it's restored in step 3 and services that
need secrets recover on the next activation.

## 3. Restore the auth state (on saturn, after it reboots)

nixos-anywhere reboots saturn into the finished system. Log in on a **TTY**
(Ctrl+Alt+F3) as `cramt` — restore *before* starting Zen/1Password so nothing
is holding the profile open. The HDDs are auto-mounted by the new config.

```bash
B=/mnt/amirani/saturn-migration-backup

# user auth state back into the home:
rsync -aHAX "$B/home/" ~/

# opnix bootstrap token → refetch secrets:
sudo cp -a "$B/opnix-token" /etc/opnix-token
sudo chown root:onepassword-secrets /etc/opnix-token && sudo chmod 0640 /etc/opnix-token
sudo systemctl restart onepassword-secrets.service

# saved Wi-Fi, if backed up:
if [ -d "$B/nm-connections" ]; then
  sudo cp -a "$B/nm-connections/." /etc/NetworkManager/system-connections/
  sudo chmod 600 /etc/NetworkManager/system-connections/*
fi
```

Start your graphical session — Zen, 1Password, GPG, Element, Steam come up
authenticated (modulo the one-time 1Password unlock noted above).

## 4. Reinstall Windows (League)

1. Boot the Windows installer (USB).
2. Install into the **150G NTFS partition** on nvme1n1 (`windows` / part1). Do
   **not** let it reformat the ESP or touch the btrfs `pool` partition.
3. Windows writes its boot files to the shared ESP.

**Dual-boot note:** NixOS `systemd-boot` does not auto-detect Windows. Either
pick Windows from the firmware boot menu (F-key at POST), or add a boot entry —
e.g. `boot.loader.systemd-boot.windows` via an extra entry, or switch saturn to
GRUB with `boot.loader.grub.useOSProber = true`. Decide this after Windows is in.

## Alternative: local USB install (no second machine)

If you can't drive nixos-anywhere from another host, boot a **nixos-unstable**
USB on saturn and run it locally:

```bash
sudo -i && export NIX_CONFIG="experimental-features = nix-command flakes"
nix run nixpkgs#git -- clone https://github.com/cramt/nixconf /tmp/nixconf
cd /tmp/nixconf && git checkout saturn-disko
nix run github:nix-community/disko#disko-install -- --flake .#saturn \
  --disk ssd_a /dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL1T766468L \
  --disk ssd_b /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E
```

Then restore as in step 3, but mount the backup HDD by-uuid first and use
`nixos-enter --root /mnt` for the `chown`/token steps (system isn't booted yet).

## Rollback

Until nixos-anywhere/disko actually runs, nothing is destroyed. Don't
`nixos-rebuild switch` or reboot saturn on the `saturn-disko` branch (its disko
fileSystems point at a btrfs pool that doesn't exist yet). `git checkout main`
restores the working ext4 config.
