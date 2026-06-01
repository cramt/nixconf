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
      # Disable USB autosuspend for the Bluetooth controller. Intel adapters
      # (AX211 here) hit firmware exceptions ("hci0: Hardware error 0x0c") and
      # reset the radio when autosuspended, dropping all connections — audio
      # cuts out and devices disconnect/reconnect.
      boot.extraModprobeConfig = "options btusb enable_autosuspend=0";
    };
  };

  hmModules.features.blueman = { config, lib, ... }: {
    options.myHomeManager.blueman.enable = lib.mkEnableOption "myHomeManager.blueman";
    config = lib.mkIf config.myHomeManager.blueman.enable {
      services.mpris-proxy.enable = true;
    };
  };
}
