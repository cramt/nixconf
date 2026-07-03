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

## 0. Pre-flight — what must survive the wipe

Everything on the SSDs is destroyed. Reproducible-from-flake state (the nix
store, HM dotfiles, opnix secrets from 1Password) does **not** need backup. What
does:

- `/home/cramt` — anything not already pushed to a git remote (downloads,
  scratch, un-pushed repos incl. `~/code/nixarr`). **Verify `~/code/nixarr` and
  `~/nixconf` are pushed first.**
- `/var/lib/nixarr-test/` — nixarr test media + state (`stateDir`, `mediaDir`).
  Re-downloadable, but back up if you care about the current test corpus.
- `/var/lib/docker`, `/var/lib/waydroid` — container/waydroid state (optional).

Confirm sizes and the HDD pool has room:

```bash
sudo du -shx /home/cramt /var/lib/nixarr-test /var/lib/docker /var/lib/waydroid 2>/dev/null | sort -rh
df -h /external_storage
```

## 1. Back up to the HDD pool

```bash
sudo mkdir -p /mnt/amirani/saturn-migration-backup
# Home minus regenerable caches:
sudo rsync -aHAX --info=progress2 \
  --exclude '.cache' --exclude '.local/share/Trash' --exclude 'Downloads/*.iso' \
  /home/cramt/ /mnt/amirani/saturn-migration-backup/home-cramt/
# Optional stateful services:
sudo rsync -aHAX --info=progress2 /var/lib/nixarr-test/ /mnt/amirani/saturn-migration-backup/nixarr-test/
# (repeat for /var/lib/docker, /var/lib/waydroid if wanted)
```

Also make sure the flake is on the remote:

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

## 5. Restore state

```bash
# HDDs auto-mount? If not, mount amirani read-only to reach the backup:
mount /dev/disk/by-uuid/fc155353-2c26-40f4-992a-204b174c270c /mnt2  # amirani
rsync -aHAX /mnt2/saturn-migration-backup/home-cramt/ /mnt/home/cramt/
rsync -aHAX /mnt2/saturn-migration-backup/nixarr-test/ /mnt/var/lib/nixarr-test/
# fix ownership if uid changed:
nixos-enter --root /mnt -c 'chown -R cramt:users /home/cramt'
```

Reboot, remove the USB.

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
