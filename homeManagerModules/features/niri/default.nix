{
  lib,
  pkgs,
  config,
  ...
}: let
  mod = "Super";
in {
  config = {
    stylix.targets.niri.enable = true;
    programs.fuzzel = {
      enable = true;
    };
    programs.niri.settings = {
      environment = {
        DISPLAY = ":1";
      };
      window-rules = [
        {
          open-fullscreen = false;
          open-maximized = false;
        }
      ];
      layout = {
        gaps = 0;
        border = {
          width = 1;
        };
      };
      input.touchpad.natural-scroll = false;
      input.keyboard.xkb = {
        layout = "dk";
        variant = "nodeadkeys";
      };
      spawn-at-startup = [
        {
          command = [
            "${lib.getExe pkgs.swaybg}"
            "-m"
            "fill"
            "-i"
            "${config.stylix.image}"
          ];
        }
        {
          command = [
            "${lib.getExe pkgs.waybar}"
          ];
        }
        {
          command = [
            "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
          ];
        }
      ];
      binds =
        {
          "${mod}+T".action.spawn = "rio";
          "${mod}+D".action.spawn = "${pkgs.fuzzel}/bin/fuzzel";

          "${mod}+Left".action."focus-column-left" = [];
          "${mod}+Right".action."focus-column-right" = [];
          "${mod}+Up".action."focus-window-up" = [];
          "${mod}+Down".action."focus-window-down" = [];
          "${mod}+H".action."focus-column-left" = [];
          "${mod}+L".action."focus-column-right" = [];
          "${mod}+K".action."focus-window-up" = [];
          "${mod}+J".action."focus-window-down" = [];
          "${mod}+Shift+Left".action."move-column-left" = [];
          "${mod}+Shift+Right".action."move-column-right" = [];
          "${mod}+Shift+Up".action."move-window-up" = [];
          "${mod}+Shift+Down".action."move-window-down" = [];
          "${mod}+Shift+H".action."move-column-left" = [];
          "${mod}+Shift+L".action."move-column-right" = [];
          "${mod}+Shift+K".action."move-window-up" = [];
          "${mod}+Shift+J".action."move-window-down" = [];
          "${mod}+Minus".action.set-column-width = ["-10%"];
          "${mod}+Plus".action.set-column-width = ["+10%"];
          "${mod}+Shift+Minus".action.set-window-height = ["-10%"];
          "${mod}+Shift+Plus".action.set-window-height = ["+10%"];
          "${mod}+Comma".action.consume-window-into-column = [];
          "${mod}+Period".action.expel-window-from-column = [];
          "${mod}+F".action."maximize-column" = [];
          "${mod}+Q".action."close-window" = [];
          "${mod}+S".action."toggle-column-tabbed-display" = [];
        }
        // (
          builtins.listToAttrs (
            builtins.map (n: {
              name = "${mod}+${builtins.toString n}";
              value = {action."focus-workspace" = n;};
            })
            (
              lib.lists.range 1 9
            )
          )
        )
        // (
          builtins.listToAttrs (
            builtins.map (n: {
              name = "${mod}+Shift+${builtins.toString n}";
              value = {action."move-column-to-workspace" = n;};
            })
            (
              lib.lists.range 1 9
            )
          )
        );
    };
  };
}
