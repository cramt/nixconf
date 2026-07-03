# Saturn → disko two-SSD btrfs pool migration

Converts saturn's two 1TB M.2 NVMe SSDs from the old split layout to a single
disko-managed btrfs pool, and reserves a 150G slot for a fresh Windows install.

**This is a from-USB reinstall, not a live rebuild.** disko repartitions and
**wipes both SSDs**. The three SATA HDDs (`/mnt/amirani`, `/mnt/titan`,
`/mnt/phoebe` → mergerfs `/external_storage`) are **not touched** — they are the
natural place to stage backups.

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
network, which is faster than these HDDs. The **only** things worth carrying are
the bits that would otherwise cost a re-authentication:

| What | Path | Why |
|------|------|-----|
| Zen profile | `~/.config/zen/` (~600M) | bookmarks (`places.sqlite`), saved logins (`key4.db` + `logins.db`), website sessions (`cookies.sqlite` + `storage/`) |
| 1Password desktop | `~/.config/1Password/` (~35M) | keeps the account registered (avoids re-adding via Secret Key / setup code) |
| opnix token | `/etc/opnix-token` (817B, root:onepassword-secrets 0640) | bootstrap service-account token; opnix can't fetch its own token, so a fresh box has no secrets until this is back |

Deliberately **skipped** (re-fetched, not backed up): the nix store, `~/code/*`
(re-clone), Steam/game installs, `/var/lib/nixarr-test` media, docker/waydroid.

> Two honesty caveats: the 1Password *local vault* is encrypted with keys tied
> to your account login, so you may still enter your account password once on
> first unlock — restoring the dir only skips re-registering the account. Zen
> logins survive only if no Firefox *primary password* is set (it isn't here).

## 1. Back up the three paths to a HDD

Back up to a **raw** HDD (`/mnt/amirani`), not the mergerfs union — the installer
can mount the raw disk by-uuid but not the mergerfs.

```bash
sudo mkdir -p /mnt/amirani/saturn-migration-backup
rsync -aHAX --info=progress2 ~/.config/zen/       /mnt/amirani/saturn-migration-backup/zen/
rsync -aHAX --info=progress2 ~/.config/1Password/ /mnt/amirani/saturn-migration-backup/1Password/
sudo cp -a /etc/opnix-token /mnt/amirani/saturn-migration-backup/opnix-token
sync
```

And make sure the flake is on the remote (so the fresh box can build itself):

```bash
cd ~/nixconf && git status && git log --oneline -1 && git push
```

## 2. Boot the NixOS installer

Write a **nixos-unstable** minimal/graphical ISO to a USB (saturn tracks
unstable). Boot it, get networking, become root, enable flakes:

```bash
sudo -i
export NIX_CONFIG="experimental-features = nix-command flakes"
# get the flake:
nix run nixpkgs#git -- clone https://github.com/cramt/nixconf /tmp/nixconf   # or your remote
cd /tmp/nixconf && git checkout saturn-disko
```

## 3. Partition + format with disko (DESTRUCTIVE)

Double-check the by-id paths in `hosts/saturn/disko.nix` still resolve on the
live system (`ls -l /dev/disk/by-id/ | grep nvme`) before running:

```bash
nix run github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  --flake /tmp/nixconf#saturn \
  --yes-wipe-all-disks
```

This wipes both SSDs, creates ESP + btrfs pool + the 150G Windows slot, and
mounts everything under `/mnt`. Verify:

```bash
mount | grep /mnt
btrfs filesystem show /mnt
```

## 4. Install

```bash
nixos-install --flake /tmp/nixconf#saturn --no-root-passwd
```

## 5. Restore the auth state

Still in the installer, with the new system mounted at `/mnt`. Mount the backup
HDD and restore:

```bash
mkdir -p /mnt2 && mount /dev/disk/by-uuid/fc155353-2c26-40f4-992a-204b174c270c /mnt2  # amirani
B=/mnt2/saturn-migration-backup

# Zen + 1Password back into the user's home (created by nixos-install):
mkdir -p /mnt/home/cramt/.config
rsync -aHAX "$B/zen/"       /mnt/home/cramt/.config/zen/
rsync -aHAX "$B/1Password/" /mnt/home/cramt/.config/1Password/
nixos-enter --root /mnt -c 'chown -R cramt:users /home/cramt/.config/zen /home/cramt/.config/1Password'

# opnix bootstrap token — restore BEFORE first boot so opnix can fetch secrets.
# Fix owner/mode inside the installed system where the group exists:
cp -a "$B/opnix-token" /mnt/etc/opnix-token
nixos-enter --root /mnt -c 'chown root:onepassword-secrets /etc/opnix-token && chmod 0640 /etc/opnix-token'
```

Reboot, remove the USB. On first boot opnix reads `/etc/opnix-token` and
provisions all the `op://Homelab/...` secrets; Zen and 1Password come up already
authenticated (modulo the one-time 1Password unlock noted above).

## 6. Reinstall Windows (League)

1. Boot the Windows installer (USB).
2. Install into the **150G NTFS partition** on nvme1n1 (`windows` / part1). Do
   **not** let it reformat the ESP or touch the btrfs `pool` partition.
3. Windows writes its boot files to the shared ESP.

**Dual-boot note:** NixOS `systemd-boot` does not auto-detect Windows. Either
pick Windows from the firmware boot menu (F-key at POST), or add a boot entry —
e.g. `boot.loader.systemd-boot.windows` via an extra entry, or switch saturn to
GRUB with `boot.loader.grub.useOSProber = true`. Decide this after Windows is in.

## Rollback

Until step 3 runs, nothing is destroyed — just don't `nixos-rebuild switch` or
reboot saturn on the `saturn-disko` branch (the disko fileSystems point at a
btrfs pool that doesn't exist yet). `git checkout main` restores the working
ext4 config.
