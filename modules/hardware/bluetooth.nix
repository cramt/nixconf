# Bluetooth support — NixOS hardware + HM blueman applet
{ ... }: {
  flake.nixosModules."features.bluetooth" = { config, lib, ... }: {
    options.myNixOS.bluetooth.enable = lib.mkEnableOption "myNixOS.bluetooth";
    config = lib.mkIf config.myNixOS.bluetooth.enable {
      services.blueman.enable = true;
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };
    };
  };

  hmModules.features.blueman = { config, lib, ... }: {
    options.myHomeManager.blueman.enable = lib.mkEnableOption "myHomeManager.blueman";
    config = lib.mkIf config.myHomeManager.blueman.enable {
      services.blueman-applet.enable = true;
      services.mpris-proxy.enable = true;
    };
  };
}
