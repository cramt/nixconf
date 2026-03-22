# DDC/CI monitor control
{ ... }: {
  flake.nixosModules."features.external-monitor-control" = { config, lib, ... }: {
    options.myNixOS.external-monitor-control.enable = lib.mkEnableOption "myNixOS.external-monitor-control";
    config = lib.mkIf config.myNixOS.external-monitor-control.enable {
      services.ddccontrol.enable = true;
    };
  };
}
