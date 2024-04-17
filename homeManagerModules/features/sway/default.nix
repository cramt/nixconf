{ ... }:

let
  mod = "Mod4";
in
{
  config = {
    security.polkit.enable = true;
    wayland.windowManager.sway = {
      enable = true;
      config = {
        modifier = mod;
        terminal = "alacritty";
        keybindings = {
          "${mod}+d" = "exec wofi --show drun";
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

      eww-wayland
      swww

      networkmanagerapplet

      wofi

      (pkgs.waybar.overrideAttrs (oldAttrs: {
        mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
      }))
    ];
  };
}
