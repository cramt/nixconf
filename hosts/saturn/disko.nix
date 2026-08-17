# Two-SSD btrfs pool for saturn — luna's `pool` technique applied to the OS drives.
#
# Both 1TB M.2 NVMe SSDs are merged into ONE btrfs filesystem created with
# `-d single -m raid1`:
#   * data   = single  → each file lives on one drive, so the full combined
#              capacity of the two btrfs members is usable (no space lost to
#              mirroring). This is what lets the nix store grow into the shared
#              pool as it pleases.
#   * metadata = raid1  → mirrored across both drives, so a single-drive failure
#              still mounts degraded and the surviving files stay readable
#              without a salvage operation.
#
# The 970 EVO additionally reserves a 150G NTFS slot for a fresh Windows install
# (League) — Windows dual-boots off the shared ESP, which lives on the 980.
#
# Drives are named by MODEL here, never by nvmeXn1: the kernel's enumeration of
# the two is not stable, and as of 2026-08-17 it is the reverse of what this file
# used to claim (the 970 EVO is nvme0n1, the 980 is nvme1n1). Nothing real depends
# on it — disko addresses by-id and fileSystems by-partlabel — but a comment that
# says nvme0n1 is an invitation to point a destructive command at the wrong disk.
#
# Both drives also carry a plain-ext4 LLM partition outside the btrfs pool; see
# "LLM streaming tier" below and docs/saturn-llm-storage.md. That leaves the
# pool at ~1.1TB usable.
#
# This intentionally replaces the old ext4 `/` (nvme0n1) + ext4 `/nix` (nvme1n1)
# split and the leftover Windows partitions. Running disko against these devices
# WIPES BOTH SSDs — see docs/saturn-disko-migration.md for the procedure.
#
# ## LLM streaming tier (/llm/primary, /llm/mirror)
#
# colibrì streams MoE expert weights off disk on every token, so decode speed is
# disk bandwidth, not compute. Two things follow, and neither works on the btrfs
# pool:
#
#   1. `compress=zstd:1` makes O_DIRECT impossible — btrfs falls back to
#      buffered I/O on compressed extents — and int4 weights are incompressible
#      noise anyway, so zstd is pure CPU burn on write plus a decompress step in
#      the read hot path. CoW and per-read csum verification are also dead weight
#      on a read-only 167-372GB blob. ext4 has none of that to disable, which is
#      the point: the weights *cannot* end up compressed because the filesystem
#      does not do it.
#   2. The engine's dual-drive mode (COLI_MODEL + COLI_MODEL_MIRROR) hashes each
#      expert to one of two drives and sums their bandwidth. It routes by path,
#      so it needs two *independent* filesystems on two *physical* drives. Two
#      directories on one btrfs pool would just be two reads of the same
#      filesystem for double the space and no gain.
#
# Sizes are deliberately asymmetric because the drives are:
#
#   * 970 EVO — TLC with a 1GB LPDDR4 DRAM cache. The better streaming drive,
#     especially for the scattered random reads expert routing generates. Gets
#     the 400G PRIMARY, which serves every expert the mirror doesn't have.
#   * 980 (non-Pro) — TLC but DRAM-less (HMB). Upstream warns DIRECT=1 is
#     "neutral to negative" on DRAM-less drives, so it gets the 200G MIRROR.
#
# 400G/200G covers both models worth running here: DeepSeek V4 Flash (167G) fits
# on BOTH, so it mirrors in full and splits ~50/50 across the drives, and
# GLM-5.2 (372G) fits the primary with a ~54% partial mirror staged by
# `coli mirror plan|stage|verify`. Partial mirrors are explicitly supported.
# colibrì weights the routing by measured per-drive bandwidth, so it handles the
# asymmetric pair on its own — no manual COLI_DISK_WEIGHTS needed.
{...}: let
  # Stable by-id paths for the two NVMe SSDs.
  ssdA = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL1T766468L"; # 980 — ESP + LLM mirror + btrfs member
  ssdB = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E"; # 970 EVO — Windows + LLM primary + btrfs member, owns the mkfs

  btrfsMountOptions = ["compress=zstd:1" "noatime"];

  # noatime: an atime write per expert read is exactly the wrong thing on the
  # streaming path. `-m 0` drops ext4's default 5% root reserve, which on a 400G
  # partition is 20G held back from a filesystem that only ever holds one
  # read-only model and is never written to by a daemon that could wedge the
  # system by filling it.
  llmMountOptions = ["noatime" "nofail"];
  llmExtraArgs = ["-m" "0"];
in {
  disko.devices.disk = {
    # ssd_a is created first (alphabetical). It carries the ESP and contributes
    # its second partition as a *secondary* btrfs device — left without `content`
    # so ssd_b's mkfs can reference it via extraArgs. A btrfs multi-device
    # filesystem can only be created once every member partition exists, so the
    # alphabetically-last disk (ssd_b) owns the filesystem definition.
    ssd_a = {
      type = "disk";
      device = ssdA;
      content = {
        type = "gpt";
        partitions = {
          # Explicit priorities. disko orders partitions by `priority` and falls
          # back to attribute-name order for ties, and builtins.sort makes no
          # stability guarantee — so leaving ties to break by name would make
          # partition NUMBERS an implementation detail. They are load-bearing
          # (the btrfs extraArgs below, and ssd_b's part1 for Windows).
          ESP = {
            priority = 100;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          # Secondary btrfs member, referenced by ssd_b's mkfs below. Explicitly
          # sized rather than 100% so the LLM partition can follow it — see the
          # note on ordering above `llm`.
          pool = {
            priority = 200;
            size = "730G";
          };
          # LLM mirror — the DRAM-less 980, so the smaller/secondary copy.
          #
          # This is LAST on the disk, and that is the whole reason saturn can get
          # these partitions without a reinstall: shrinking a btrfs member frees
          # space at the END of the drive, so a new tail partition is the only
          # thing that can be added in place. Putting it before the pool would
          # mean moving the pool's start sector, i.e. relocating a terabyte.
          # Keeping it last also leaves the ESP, Windows and both pool members on
          # their existing partition numbers.
          #
          # 100% (not an explicit 200G) so it absorbs whatever the drive actually
          # has past the pool — the exact usable capacity of a "1TB" NVMe is not
          # worth hardcoding, and a few hundred MiB either way is noise against a
          # 167G model. Works out to ~200G.
          llm = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/llm/mirror";
              mountOptions = llmMountOptions;
              extraArgs = llmExtraArgs;
            };
          };
        };
      };
    };

    ssd_b = {
      type = "disk";
      device = ssdB;
      content = {
        type = "gpt";
        partitions = {
          # Empty NTFS-typed slot for a fresh Windows install (League). Left
          # without `content` so the Windows installer owns it; Windows boots
          # off the shared ESP on ssd_a. This MUST stay part1:
          # scripts/saturn-windows-image.sh and scripts/windows-vm.sh both
          # address it as `<ssd_b by-id>-part1`.
          windows = {
            priority = 100;
            size = "150G";
            type = "0700"; # Microsoft basic data (NTFS)
          };
          # Primary btrfs member; owns the mkfs for the whole pool. Explicitly
          # sized so the LLM partition can be the tail one (see ssd_a's `llm`).
          pool = {
            priority = 200;
            size = "381G";
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "nvme-pool"
                "-d"
                "single"
                "-m"
                "raid1"
                # Still part2: both LLM partitions go at the END of their drives,
                # so nothing here gets renumbered.
                "${ssdA}-part2"
              ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = btrfsMountOptions;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsMountOptions;
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = btrfsMountOptions;
                };
              };
            };
          };
          # LLM primary — the 970 EVO has DRAM, so it takes the full model and
          # serves every expert the mirror doesn't hold. Tail partition for the
          # same reason as ssd_a's; works out to ~400G.
          llm = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/llm/primary";
              mountOptions = llmMountOptions;
              extraArgs = llmExtraArgs;
            };
          };
        };
      };
    };
  };
}
