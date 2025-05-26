{
  pkgs,
  lib,
  ...
}: let
  mod = "SUPER";
in {
  config = {
    wayland.windowManager.hyprland = {
      enable = true;
      settings = {
        general = {
          gaps_in = 0;
          gaps_out = 0;
        };

        input = {
          kb_layout = "dk";
          kb_variant = "nodeadkeys";
        };

        animations = {
          enabled = "yes";
        };

        bindm = [
          "${mod}, mouse:272, movewindow"
          "${mod}, mouse:273, resizewindow"
        ];

        windowrule = [
          "tile, class:.*"
          "suppressevent maximize, class:.*"
          "nomaxsize, class:.*"
        ];

        bind =
          [
            "${mod}, Q, killactive,"
            "${mod}, S, togglegroup"
            "${mod}, T, exec, ${pkgs.rio}/bin/rio"
            "${mod}, D, exec, ${pkgs.tofi}/bin/tofi-drun | xargs ${pkgs.hyprland}/bin/hyprctl dispatch exec --"
            "${mod}, mouse_down, workspace, e+1"
            "${mod}, mouse_up, workspace, e-1"
            "${mod}, G, togglefloating,"
            "${mod}, Tab, cyclenext,"
          ]
          ++ (builtins.concatLists (lib.attrsets.mapAttrsToList (bind: dir: [
              "${mod}, ${bind}, movefocus, ${dir}"
              "${mod} SHIFT, ${bind}, movewindow, ${dir}"
            ]) {
              H = "l";
              left = "l";
              right = "r";
              L = "r";
              up = "u";
              K = "u";
              down = "d";
              J = "d";
            }))
          ++ (
            builtins.concatLists (builtins.genList (
                i: let
                  ws = i + 1;
                in [
                  "${mod}, code:1${toString i}, workspace, ${toString ws}"
                  "${mod} SHIFT, code:1${toString i}, movetoworkspace, ${toString ws}"
                ]
              )
              9)
          );
      };
    };
  };
}
