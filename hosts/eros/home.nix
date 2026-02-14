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
    bundles.general.enable = true;
  };

  home.stateVersion = "25.11";

  wayland.windowManager.sway = let
    term = "${pkgs.foot}/bin/foot";
  in {
    enable = true;

    config = {
      modifier = "Mod4";
      bars = []; # kiosk: no bar

      # Escape hatch: Mod+Enter opens a terminal
      # (This is compositor-level, so it should work even if Moonlight is focused.)
      keybindings = lib.mkOptionDefault {
        "Mod4+Return" = "exec ${term}";

        # Optional second hatch, in case you ever remap Mod:
        "Mod4+Shift+Return" = "exec ${term}";
      };

      # Start Moonlight on login
      startup = [
        {
          command = "${pkgs.moonlight-qt}/bin/moonlight-qt";
          always = true;
        }
      ];
    };

    extraConfig = ''
      # A named variable is handy if you tweak later
      set $term ${term}

      # If you want a less “Mod-heavy” hatch, pick something obscure:
      # bindsym Ctrl+Alt+t exec $term

      # Optional: don’t blank displays
      exec_always ${pkgs.swayidle}/bin/swayidle -w \
        timeout 0 'swaymsg "output * dpms on"'

      output * bg #000000 solid_color
    '';
  };
}
