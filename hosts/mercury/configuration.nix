# mercury — Terasic DE25-Nano, an Agilex 5 SoC FPGA dev board. This configures the
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
    pkgs.runCommand "mercury-boot.scr.uimg" {
      nativeBuildInputs = [pkgs.buildPackages.ubootTools];
    } ''
      cat > boot.cmd <<EOF
      echo "mercury: enabling HPS<->FPGA bridges";
      bridge enable;
      echo "mercury: handing off to extlinux on mmc 0:2";
      sysboot mmc 0:2 any ${syslinuxAddr} /boot/extlinux/extlinux.conf;
      EOF
      mkimage -A arm64 -O linux -T script -C none -d boot.cmd "$out"
    '';

  # CONFIG_LOCALVERSION_AUTO appends "-g<sha>" from git describe. fetchFromGitHub
  # gives a tarball with no .git, so that suffix silently vanishes and stops
  # matching modDirVersion (which then breaks module loading). Pin it off rather
  # than encode a hash we can't reproduce.
  # Named for the board, not the host: this feeds the kernel's `configfile`, so a
  # host rename would otherwise change the kernel's store path and throw away a
  # ~26 min cached ARM build for nothing.
  kernelConfig =
    pkgs.runCommand "de25-nano-kernel.config" {} ''
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

  image.baseName = "mercury";

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

  # nixosModules.default ships lix/zfs/quadlet, none of which has cached aarch64
  # builds worth having on a 957 MB board; quadlet auto-enables when its option
  # is null (transitively pulling podman + matplotlib at build time). Same
  # reasoning as eros — but note stylix deliberately stays ON here, see below.
  nix.package = lib.mkForce pkgs.nix;
  boot.supportedFilesystems.zfs = lib.mkForce false;
  virtualisation.quadlet.enable = false;

  myNixOS = {
    services.sshd.enable = true;

    # Unlike eros, mercury keeps the general bundle and stylix on. It isn't a
    # desktop bundle — it's the fleet's system baseline (locale, timezone, nh,
    # comma, trippy, udev) — and it's also what supplies stylix.image/cursor/
    # fonts. stylix can't just be switched off here either: hm-base/default-hm.nix
    # reads config.stylix.enable directly, so with stylix's HM module absent the
    # whole evaluation dies on `attribute 'stylix' missing`. eros escapes that
    # only by importing none of the repo's HM modules at all.
    bundles.general = {
      enable = true;
      stylixAsset = ../../media/artemis2_1.jpg;
    };
  };

  # mercury opts out of myNixOS.bundles.users for the same reason eros does: that
  # bundle puts every user in libvirtd/docker/gamemode/storage/pipewire, none of
  # which exist here, so useradd fails during activation. Wire the account and
  # its keys directly instead.
  #
  # sshd here is key-only (the module sets PasswordAuthentication = false and
  # PermitRootLogin = prohibit-password) and nothing sets a password, so without
  # these keys the board boots onto the network completely unreachable — the
  # serial console can't rescue it either, since an account with no password set
  # is locked rather than empty.
  programs.zsh.enable = true;

  users.users = {
    cramt = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = (import ../../myLib/keys.nix).alex;
    };

    # `just deploy` activates as root over SSH, so deploy-rs needs this
    # independently of the cramt account. mercury is already in deploy.nodes.
    root.openssh.authorizedKeys.keys = (import ../../myLib/keys.nix).alex;
  };

  security.sudo.wheelNeedsPassword = false;

  # ./home.nix is written against myHomeManager.*, and those options only exist
  # if the repo's HM module set is imported — bundles.users does that per user,
  # and we opted out above, so replicate its import list here. Without this the
  # file is inert: home-manager.users evaluates empty and nothing is applied.
  home-manager = {
    # Deliberately no useGlobalPkgs/useUserPackages, unlike eros: the repo's
    # hmModules.default sets HM-side `nixpkgs` options, and useGlobalPkgs asserts
    # against those. bundles.users sets neither for the same reason.
    backupFileExtension = "hm-bak";
    extraSpecialArgs = {inherit inputs;};

    users.cramt = {pkgs, ...}: let
      hm = inputs.self.outputs.homeManagerModules;

      # Exactly the features hm-bundles/general.nix switches on, and nothing
      # else. bundles.users imports *every* feature and bundle, which is fine on
      # a desktop but here dragged niri (a whole Wayland compositor, ~300 Rust
      # crates), 1Password, GTK/Qt/Kvantum theming and Blender presets into the
      # closure — 490 derivations compiled from source on the ARM runner for a
      # board with no display at all. Keep this list in sync with that bundle.
      cliFeatures = [
        "btop"
        "fzf"
        "git"
        "gpg-agent"
        "lazygit"
        "neovim"
        "nix-index"
        "nushell"
        "ssh"
        "starship"
        "yazi"
        "zellij"
        "zoxide"
        "zsh"
      ];
    in {
      imports =
        [
          (import ./home.nix)
          hm.default
          hm.bundles.general
          inputs.nix-index-database.homeModules.nix-index
        ]
        ++ map (n: hm.features.${n}) cliFeatures;

      # niri-flake's HM module rides in on sharedModules (see below) and writes
      # ~/.config/niri/config.kdl, which references the compositor binary — that
      # alone makes the ARM runner build niri and ~300 Rust crates, even though
      # programs.niri.enable is false. null means "don't manage the file".
      programs.niri.config = lib.mkForce null;

      # hm-features/git.nix hardcodes 1Password's op-ssh-sign as the SSH signing
      # program, which puts the whole 1Password GUI in this board's closure for
      # a machine that has no GUI and no 1Password. ssh-keygen is the stock
      # signer and keeps signed commits working over SSH.
      programs.git.settings.gpg.ssh.program =
        lib.mkForce (lib.getExe' pkgs.openssh "ssh-keygen");
    };

    # sharedModules is deliberately left alone (eros clears it, we can't): it is
    # how stylix's HM module arrives, and hm-base/default-hm.nix reads
    # config.stylix.enable directly, so clearing it makes `attribute 'stylix'
    # missing` at eval.
  };

  # 4 cores and ~957 MB: this board substitutes, it never compiles. `just deploy`
  # already builds locally and only copies closures out, so this holds anyway.
  nix.settings.max-jobs = 1;

  system.stateVersion = "26.05";
}
