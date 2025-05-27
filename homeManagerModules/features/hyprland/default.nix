{
  pkgs,
  lib,
  config,
  ...
}: let
  mod = "SUPER";
  cfg = config.myHomeManager;
in {
  config = {
    myHomeManager.rofi.enable = true;
    myHomeManager.waybar.enable = true;
    wayland.windowManager.hyprland = {
      enable = true;
      settings = {
        general = {
          gaps_in = 0;
          gaps_out = 0;
        };

        exec-once = [
          "${pkgs.waybar}/bin/waybar"
          "${pkgs.hyprswitch}/bin/hyprswitch init &"
        ];

        input = {
          kb_layout = "dk";
          kb_variant = "nodeadkeys";
        };

        animations = {
          enabled = "yes";
        };

        monitor = builtins.concatLists (lib.attrsets.mapAttrsToList (
            name: options: let
              res = "${builtins.toString options.res.width}x${builtins.toString options.res.height}";
              pos = "${builtins.replaceStrings [" "] ["x"] options.pos}";
            in [
              "desc:${name}, ${res}, ${pos}, 1"
              "${name}, ${res}, ${pos}, 1"
            ]
          )
          cfg.monitors);

        workspace =
          lib.attrsets.mapAttrsToList (
            name: options: "${options.workspace}, monitor:desc:${name}"
          )
          cfg.monitors;

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
            "${mod}, Tab, exec, ${pkgs.hyprswitch}/bin/hyprswitch gui --mod-key super --key Tab --show-workspaces-on-all-monitors --close mod-key-release"
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
