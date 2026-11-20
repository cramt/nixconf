# Secure Boot on for Windows' sake (its anti-cheat wants it), with Linux
# still booting: NixOS's own Limine support signs Limine with keys sbctl
# generates and enrolls on the first install, Microsoft's alongside (Windows'
# boot manager, GPU option ROMs) plus the firmware's built-in ones. Limine
# loads the kernel itself, so nothing else needs signing. The firmware has to
# be in setup mode for that first install; then turn Secure Boot on in it.
#
# The keys live in /var/lib/sbctl only: losing them means resetting the
# firmware to setup mode and installing again, which enrolls new ones.
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
          # Defaults: --microsoft --firmware-builtin.
          autoEnrollKeys.enable = true;
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
