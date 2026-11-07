# saturn's two NVMe SSDs: one per OS.
#
#   * 980 (ssd_a): Linux. ESP + one btrfs filesystem filling the rest.
#   * 970 EVO (nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E): Windows, and not
#     declared here at all. Windows setup owns the whole disk, ESP included,
#     so reinstalling either OS never touches the other's disk.
#
# The 980 gets Linux because the split could then be done in place
# (docs/saturn-dual-boot.md): it already held the ESP and the larger pool
# member, and its trailing partition could be deleted so the pool grows into
# it. The disk keeps the name ssd_a because disko derives partition labels
# from it (disk-ssd_a-ESP, disk-ssd_a-pool) and fileSystems mount by those.
#
# Drives are named by MODEL, never by nvmeXn1: the kernel's enumeration of the
# two is not stable (as of 2026-08-17 the 970 EVO is nvme0n1).
{...}: let
  ssdA = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL1T766468L";

  btrfsMountOptions = ["compress=zstd:1" "noatime"];
in {
  disko.devices.disk.ssd_a = {
    type = "disk";
    device = ssdA;
    content = {
      type = "gpt";
      partitions = {
        # Explicit priorities pin partition numbers rather than leaving them to
        # attribute-name order.
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
        pool = {
          priority = 200;
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = ["-L" "nvme-pool"];
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
}
