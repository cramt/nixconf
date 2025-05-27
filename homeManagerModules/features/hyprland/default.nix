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
    stylix.targets.hyprlock.useWallpaper = false;
    programs.hyprlock = {
      enable = true;
      settings = {
        animations = {
          enabled = "true";
        };
        background = {
          path = "screenshot";
          blur_passes = 3;
        };
        label = [
          {
            text = "$TIME";
            font_size = "90";
            halign = "left";
            valighn = "top";
          }
        ];
      };
    };
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof ${pkgs.hyprlock}/bin/hyprlock || ${pkgs.hyprlock}/bin/hyprlock";
          before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
          after_sleep_cmd = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
        };
        listener = [
          {
            timeout = 330;
            on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
          }
          {
            timeout = 300;
            on-timeout = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
            on-resume = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
          }
        ];
      };
    };
    wayland.windowManager.hyprland = {
      enable = true;
      settings = {
        general = {
          "col.inactive_border" = lib.mkForce "rgba(00000000)";
          gaps_in = 0;
          gaps_out = 0;
          border_size = 2;
        };

        exec-once = [
          "${pkgs.waybar}/bin/waybar -b hyprland"
          "${pkgs.hyprswitch}/bin/hyprswitch init &"
        ];

        input = {
          kb_layout = "dk";
          kb_variant = "nodeadkeys";
        };

        animations = {
          enabled = "yes";
        };

        group = {
          groupbar = {
            font_size = "20";
            keep_upper_gap = false;
            indicator_height = 0;
          };
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
            "${mod}, Y, changegroupactive, f"
            "${mod}, O, changegroupactive, b"
            "${mod}, F, fullscreen, 1"
            ", Print, exec, exec ${pkgs.sway-contrib.grimshot}/bin/grimshot --notify copy area"
          ]
          ++ (builtins.concatLists (lib.attrsets.mapAttrsToList (bind: dir: [
              "${mod}, ${bind}, movefocus, ${dir}"
              "${mod} SHIFT, ${bind}, movewindoworgroup, ${dir}"
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
