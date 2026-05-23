# Secure Boot via lanzaboote
{ inputs, ... }: {
  flake.nixosModules."features.secureboot" = { config, lib, pkgs, ... }: {
    imports = [
      inputs.lanzaboote.nixosModules.lanzaboote
    ];
    options.myNixOS.secureboot.enable = lib.mkEnableOption "myNixOS.secureboot";
    config = lib.mkIf config.myNixOS.secureboot.enable {
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.lanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
      };
      environment.systemPackages = [
        pkgs.sbctl
      ];
    };
  };
}
