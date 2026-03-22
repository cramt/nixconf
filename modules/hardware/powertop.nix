# Power management with powertop
{ ... }: {
  flake.nixosModules."features.powertop" = { config, lib, pkgs, ... }: {
    options.myNixOS.powertop.enable = lib.mkEnableOption "myNixOS.powertop";
    config = lib.mkIf config.myNixOS.powertop.enable {
      powerManagement.powertop.enable = true;
      environment.systemPackages = with pkgs; [
        powertop
      ];
    };
  };
}
