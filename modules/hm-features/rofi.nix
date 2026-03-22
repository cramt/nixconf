{ ... }: {
  hmModules.features.rofi = { config, lib, pkgs, ... }: let
    rofiShowCalc = pkgs.writeShellScriptBin "rofi_show_calc" ''
      if [[ -z "$1" ]]; then
          echo "Show calculator"
      else
          kill `pidof rofi`
          rofi -show calc
      fi
    '';
  in {
    options.myHomeManager.rofi.enable = lib.mkEnableOption "myHomeManager.rofi";
    config = lib.mkIf config.myHomeManager.rofi.enable {
      programs.rofi = rec {
        enable = true;
        extraConfig = {
          modi = lib.strings.concatStrings (lib.strings.intersperse "," [
            "drun" "calc" "emoji" "powermenu:${pkgs.rofi-power-menu}/bin/rofi-power-menu" "top"
          ]);
        };
        plugins = (with pkgs; [ rofi-calc rofi-emoji rofi-top ]) ++ [ pkgs.rofi-power-menu ];
      };
    };
  };
}
