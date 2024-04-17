{ lib, pkgs, ... }:

let
  mod = "Mod4";
in
{
  config = {
    wayland.windowManager.sway = {
      enable = true;
      config = {
        modifier = mod;
        terminal = "alacritty";
        menu = "wofi --show drun";
        keybindings = {
          "print" = "print exec grimshot --notify copy area";
        };
        gaps = {
          inner = 0;
          outer = 0;
          smartBorders = "on";
        };
      };
    };

    myHomeManager.wofi.enable = lib.mkDefault true;
    home.packages = with pkgs; [
      grim
      slurp
      wl-clipboard

      eww
      swww

      networkmanagerapplet

      wofi
      waybar
    ];
  };
}
