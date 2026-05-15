{device ? throw "Set this to your disk device, e.g. /dev/sda", ...}: let
  # Stable by-id paths for the two data drives on luna.
  # sda: 2TB Seagate Barracuda  (alphabetically first - holds empty partition slots)
  # sdc: 4TB Toshiba HDWG440    (alphabetically second - hosts the btrfs filesystems)
  dataA = "/dev/disk/by-id/ata-ST2000DM008-2UB102_WFL5X8W0";
  dataB = "/dev/disk/by-id/ata-TOSHIBA_HDWG440_12X0A02GFZ0G";

  # Vault partition is sized to the smaller drive's allocation (mirrored 1:1).
  vaultSize = "100G";

  btrfsMountOptions = ["compress=zstd:3" "noatime"];
in {
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        inherit device;
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
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
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };

      # disk_a is created and partitioned first (alphabetical order). Its
      # partitions are intentionally left without `content` - they become the
      # secondary devices that disk_b's btrfs mkfs commands reference via
      # extraArgs. btrfs raid filesystems can only be mounted when all member
      # devices are present, so we let the alphabetically-last disk own the
      # filesystem definition.
      disk_a = {
        type = "disk";
        device = dataA;
        content = {
          type = "gpt";
          partitions = {
            vault = {size = vaultSize;};
            pool = {size = "100%";};
          };
        };
      };

      disk_b = {
        type = "disk";
        device = dataB;
        content = {
          type = "gpt";
          partitions = {
            # Vault: btrfs raid1 across disk_a-part1 + disk_b-part1.
            # Data AND metadata are mirrored - this is the "data I cannot lose"
            # half. Checksums let btrfs detect bit rot and auto-heal from the
            # surviving copy.
            vault = {
              size = vaultSize;
              content = {
                type = "btrfs";
                extraArgs = [
                  "-L"
                  "vault"
                  "-d"
                  "raid1"
                  "-m"
                  "raid1"
                  "${dataA}-part1"
                ];
                subvolumes = {
                  "@vault" = {
                    mountpoint = "/vault";
                    mountOptions = btrfsMountOptions;
                  };
                };
              };
            };

            # Pool: btrfs across disk_a-part2 + disk_b-part2, but with
            # `-d single -m raid1`. Data is single-profile (each file lives on
            # one drive, full ~4TB usable across the two pool partitions), but
            # metadata is mirrored so a single-drive failure leaves the
            # filesystem mountable in degraded mode and the surviving files
            # readable without a salvage operation.
            pool = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [
                  "-L"
                  "pool"
                  "-d"
                  "single"
                  "-m"
                  "raid1"
                  "${dataA}-part2"
                ];
                subvolumes = {
                  "@pool" = {
                    mountpoint = "/pool";
                    mountOptions = btrfsMountOptions;
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
