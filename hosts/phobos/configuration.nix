# phobos — Terasic DE25-Nano, an Agilex 5 SoC FPGA dev board. This configures the
# HPS side only: 2x Cortex-A76 + 2x Cortex-A55, ~957 MB LPDDR4, gigabit ethernet,
# microSD. The FPGA fabric sits alongside and is not managed from here.
#
# Boot chain, reverse-engineered off the stock card (2026-08):
#
#   QSPI (SDM reads at power-on: FPGA bitstream + U-Boot SPL + DDR/EMIF setup)
#     -> SPL loads u-boot.itb from the SD card's FAT partition
#       -> our boot.scr.uimg: `bridge enable`, then sysboot
#         -> /boot/extlinux/extlinux.conf on the ext4 root (NixOS generations)
#
# The QSPI half is deliberately untouched. Regenerating it needs Quartus Prime
# Pro (proprietary, x86-only, not in nixpkgs), and it carries the DDR controller
# config — without a valid one the ARM cores have no working RAM. Happily the
# stock U-Boot already has sysboot/extlinux/distro_bootcmd compiled in, so
# everything above SPL is ours with no bootloader rebuild at all.
#
# Serial is the only console (115200 on ttyS0); HDMI is driven from the fabric,
# so there is no framebuffer unless an FPGA design provides one.
{
  inputs,
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}: let
  firmware = ./firmware;

  # U-Boot loads a boot script at ${scriptaddr} (0x81000000), so sysboot must
  # stage extlinux.conf elsewhere or it overwrites the script mid-execution.
  # DRAM is 0x80000000..0xBFFFFFFF; this clears kernel_addr_r (0x82000000) and
  # fdt_addr_r (0x86000000).
  syslinuxAddr = "0x88000000";

  # Terasic's stock script hardcodes fatload+booti, which throws away NixOS
  # generations. U-Boot scans p1 before p2 and checks extlinux before scripts
  # *within* each partition, so a script on the FAT partition still wins — we
  # use that to keep `bridge enable` (without it the HPS<->FPGA bridges stay
  # down and any fabric access faults) and then hand off to extlinux on p2.
  bootScript =
    pkgs.runCommand "phobos-boot.scr.uimg" {
      nativeBuildInputs = [pkgs.buildPackages.ubootTools];
    } ''
      cat > boot.cmd <<EOF
      echo "phobos: enabling HPS<->FPGA bridges";
      bridge enable;
      echo "phobos: handing off to extlinux on mmc 0:2";
      sysboot mmc 0:2 any ${syslinuxAddr} /boot/extlinux/extlinux.conf;
      EOF
      mkimage -A arm64 -O linux -T script -C none -d boot.cmd "$out"
    '';

  # CONFIG_LOCALVERSION_AUTO appends "-g<sha>" from git describe. fetchFromGitHub
  # gives a tarball with no .git, so that suffix silently vanishes and stops
  # matching modDirVersion (which then breaks module loading). Pin it off rather
  # than encode a hash we can't reproduce.
  kernelConfig =
    pkgs.runCommand "phobos-kernel.config" {} ''
      sed 's/^CONFIG_LOCALVERSION_AUTO=y$/# CONFIG_LOCALVERSION_AUTO is not set/' \
        ${firmware}/kernel.config > "$out"
    '';

  # Extracted verbatim from the running stock board via /proc/config.gz, so this
  # is the config Terasic actually validated rather than a reconstruction. Every
  # option NixOS requires (systemd's namespaces/seccomp/cgroups/tmpfs-ACL set) is
  # already present, and all MMC drivers are =y so the initrd finds root without
  # any modules. Mainline has Agilex 5 since 6.6, but socfpga_agilex5_de25_nano
  # exists only in Terasic's fork — revisit once the board DT lands upstream.
  de25Kernel = pkgs.linuxManualConfig {
    version = "6.12.11";
    modDirVersion = "6.12.11";
    src = inputs.terasic-linux-socfpga;
    configfile = kernelConfig;
    allowImportFromDerivation = true;
  };
in {
  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  nixpkgs = {
    hostPlatform = "aarch64-linux";
    config.allowUnfree = true;
  };

  boot = {
    kernelPackages = pkgs.linuxPackagesFor de25Kernel;

    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };

    # Matches the DTB's stdout-path. No framebuffer exists on this board.
    kernelParams = ["console=ttyS0,115200"];
    consoleLogLevel = 7;
  };

  # NixOS builds its initrd for a general-purpose machine: sd-image.nix switches on
  # hardware.enableAllHardware and kernel.nix adds its own defaults, which together
  # ask for ~110 modules (3w-9xxx, pata_*, hid_*, ext2, tpm-crb). makeModulesClosure
  # runs with allowMissing = false, so every one Terasic's config doesn't build is a
  # hard build failure — 3w-9xxx, a 3ware RAID driver, is simply the first one hit.
  # This is fixed hardware and the whole root path (Cadence SDHCI, ext4) is =y, so
  # the honest initrd module set is empty. Dropping all-hardware also drops
  # enableRedistributableFirmware, keeping linux-firmware out of a 957 MB board.
  hardware.enableAllHardware = lib.mkForce false;
  boot.initrd = {
    includeDefaultModules = false;
    availableKernelModules = lib.mkForce [];
  };

  hardware.deviceTree = {
    enable = true;
    name = "intel/socfpga_agilex5_de25_nano.dtb";
    package = lib.mkDefault "${config.boot.kernelPackages.kernel}/dtbs";
  };

  image.baseName = "phobos";

  sdImage = {
    compressImage = false;

    # Only u-boot.itb (~1 MB) and boot.scr.uimg go here; the kernel and DTB live
    # on the ext4 root so extlinux can version them per generation.
    firmwareSize = 64;
    firmwarePartitionName = "DE25BOOT";

    # Byte-for-byte from the stock card. This is what the SPL in QSPI expects to
    # find, and it is rebuildable from terasic/u-boot-socfpga + arm-trusted-
    # firmware if we ever need to — but not worth the risk while the stock one
    # already speaks extlinux.
    populateFirmwareCommands = ''
      cp ${firmware}/u-boot.itb firmware/u-boot.itb
      cp ${bootScript} firmware/boot.scr.uimg
    '';

    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} -d ./files/boot
    '';
  };

  # nixosModules.default ships stylix/lix/zfs/quadlet. None of it has cached
  # aarch64 builds worth having on a 957 MB board, and quadlet auto-enables when
  # its option is null (transitively pulling podman + matplotlib at build time).
  # Same reasoning as eros.
  stylix.enable = lib.mkForce false;
  nix.package = lib.mkForce pkgs.nix;
  boot.supportedFilesystems.zfs = lib.mkForce false;
  virtualisation.quadlet.enable = false;

  myNixOS = {
    services.sshd.enable = true;
  };

  # 4 cores and ~957 MB: this board substitutes, it never compiles. `just deploy`
  # already builds locally and only copies closures out, so this holds anyway.
  nix.settings.max-jobs = 1;

  system.stateVersion = "26.05";
}
