{
  config,
  pkgs,
  lib,
  ...
}: {
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    bundles.general.enable = true;
    bundles.development.enable = true;
    insight-driver.enable = true;
    hyprland = {
      enable = false;
      exec = "firefox --kiosk https://example.com";
    };
    monitors = [
      {
        port = "HDMI-A-1";
        name = "TODO";
        res = {
          width = 1920;
          height = 1080;
        };
        pos = {
          x = 0;
          y = 0;
        };
        workspace = 1;
        transform = 0;
        refresh_rate = null;
      }
    ];
  };

  # nix-xilinx's FHS wrappers read this to find the imperative Vivado install
  # (AMD's installer can't be packaged); tmpfiles creates /pool/Xilinx in configuration.nix.
  xdg.configFile."xilinx/nix.sh".text = ''
    INSTALL_DIR=/pool/Xilinx
    VERSION=2026.1
  '';

  home.stateVersion = "26.05";
}
