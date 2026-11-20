# Secure Boot on for Windows' sake (its anti-cheat wants it), with Linux
# still booting: NixOS's own Limine support signs Limine with keys sbctl
# generates on the first install. Limine loads the kernel itself, so nothing
# else needs signing.
#
# Enrolling them is a one-time manual step, as root, with the firmware in
# setup mode and (AMI/MSI) its Secure Boot Mode set to Custom, which is what
# lets the OS write the key variables at all:
#   chattr -i /sys/firmware/efi/efivars/{PK,KEK,db}-*
#   sbctl enroll-keys --microsoft
# Microsoft's keys go alongside ours: Windows' boot manager and the GPU's
# option ROM are signed with them. Not autoEnrollKeys: the installer neither
# clears efivarfs' immutable flag nor tries again once the keys exist, so on
# saturn it generated them and enrolled nothing (2026-11-20). Then turn
# Secure Boot on in the firmware.
#
# The keys live in /var/lib/sbctl only: losing them means resetting the
# firmware to setup mode, installing again for new ones and enrolling those.
{...}: {
  flake.nixosModules."features.secureboot" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.secureboot;
  in {
    options.myNixOS.secureboot = {
      enable = lib.mkEnableOption "Secure Boot (Limine, keys enrolled on the first install in setup mode)";
      memtest86 = lib.mkEnableOption "a memtest86+ entry, signed like Limine";
    };
    config = lib.mkIf cfg.enable {
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.limine = {
        enable = true;
        secureBoot = {
          enable = true;
          autoGenerateKeys = true;
        };
        additionalFiles = lib.mkIf cfg.memtest86 {
          "efi/memtest86/memtest.efi" = pkgs.memtest86plus.efi;
        };
        extraEntries = lib.mkIf cfg.memtest86 ''
          /memtest86+
            protocol: efi
            path: boot():/efi/memtest86/memtest.efi
        '';
      };
      environment.systemPackages = [pkgs.sbctl];
    };
  };
}
