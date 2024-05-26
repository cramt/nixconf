{ pkgs, lib, ... }:
let
  rofiShowCalc = pkgs.writeShellScriptBin "rofi_show_calc" ''
    if [[ -z "$1" ]]; then
        echo "Show calculator"
    
    else
        kill `pidof rofi` 
        # so rofi doesn't complain "can't launch rofi inside rofi"
        rofi -show calc
    fi
  '';
in
{
  programs.rofi = rec {
    enable = true;
    extraConfig = {
      modi = lib.strings.concatStrings (lib.strings.intersperse "," [
        "drun"
        "calc"
        "emoji"
        "powermenu:${pkgs.rofi-power-menu}/bin/rofi-power-menu"
        "top"
      ]);
    };
    plugins =
      (map
        (x: x.override {
          rofi-unwrapped = pkgs.rofi-wayland-unwrapped;
        })
        (with pkgs; [
          rofi-calc
          rofi-emoji
          rofi-top
        ])) ++ [
        pkgs.rofi-power-menu
      ];

    package = pkgs.rofi-wayland.override {
      plugins = plugins;
    };
  };
}
