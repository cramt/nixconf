{
  input,
  inputs,
  outputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    outputs.homeManagerModules.default
  ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    hyprland.enable = false;
    bundles.general.enable = true;
    bundles.development.enable = true;
    btop.hardware-accel = "rocm";
    bundles.graphical.enable = true;
    bundles.gaming.enable = true;
    obs.enable = true;
    git.signingKey = "C2B9D34D979B6063";
    jujutsu = {
      enable = true;
      signingKey = "C2B9D34D979B6063";
    };
    monitors = import ./monitors.nix;
    waybar.monitors = ["DP-2"];
  };

  home.stateVersion = "25.05";
}
