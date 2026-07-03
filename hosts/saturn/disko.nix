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
# nvme1n1 (970 EVO) additionally reserves a 150G NTFS slot for a fresh Windows
# install (League) — Windows dual-boots off the shared ESP on nvme0n1. That
# leaves the pool at ~1.7TB usable (full 980 + ~780G of the 970).
#
# This intentionally replaces the old ext4 `/` (nvme0n1) + ext4 `/nix` (nvme1n1)
# split and the leftover Windows partitions. Running disko against these devices
# WIPES BOTH SSDs — see docs/saturn-disko-migration.md for the procedure.
{...}: let
  # Stable by-id paths for the two NVMe SSDs.
  ssdA = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL1T766468L"; # nvme0n1 — carries the ESP + a btrfs member
  ssdB = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E"; # nvme1n1 — btrfs member, owns the mkfs

  btrfsMountOptions = ["compress=zstd:1" "noatime"];
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
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          pool = {size = "100%";}; # secondary btrfs member, referenced by ssd_b below
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
          # off the shared ESP on ssd_a. priority 1000 → this is part1, so the
          # btrfs `pool` member (100%, priority 9001) is part2.
          windows = {
            size = "150G";
            type = "0700"; # Microsoft basic data (NTFS)
          };
          pool = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "nvme-pool"
                "-d"
                "single"
                "-m"
                "raid1"
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
        };
      };
    };
  };
}
