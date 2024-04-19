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
        input = {
          "*" = {
            xkb_layout = "dk";
            xkb_variant = "nodeadkeys";
          };
        };
        keybindings = lib.mkOptionDefault
          {
            "print" = "print exec grimshot --notify copy area";
          };
        bars = [
          {
            command = "${pkgs.waybar}/bin/waybar";
          }
        ];
        gaps = {
          inner = 0;
          outer = 0;
          smartBorders = "on";
        };
        colors = {
          background = "#f8f8f2";
          focused = {
            background = "#4d0426";
            border = "#4d0426";
            childBorder = "#4d0426";
            indicator = "#ff92df";
            text = "#f8f8f2";
          };
          focusedInactive = {
            background = "#44475A";
            border = "#44475A";
            childBorder = "#44475A";
            indicator = "#44475A";
            text = "#f8f8f2";
          };
          unfocused = {
            background = "#1d212a";
            border = "#44475A";
            childBorder = "#1d212a";
            indicator = "#1d212a";
            text = "#f8f8f2";
          };
          urgent = {
            background = "#f05c8e";
            border = "#44475A";
            childBorder = "#f05c8e";
            indicator = "#f05c8e";
            text = "#f8f8f2";
          };
          placeholder = {
            background = "#1d212a";
            border = "#1d212a";
            childBorder = "#1d212a";
            indicator = "#1d212a";
            text = "#f8f8f2";
          };
        };
      };
    };

    myHomeManager.wofi.enable = lib.mkDefault
      true;
    myHomeManager.waybar.enable = lib.mkDefault
      true;
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
