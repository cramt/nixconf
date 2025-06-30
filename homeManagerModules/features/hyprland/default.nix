{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  mod = "SUPER";
  cfg = config.myHomeManager;
in {
  config = {
    home.packages = [inputs.astal.packages.${pkgs.system}.default];
    myHomeManager.rofi.enable = true;
    myHomeManager.waybar.enable = true;
    stylix.targets.hyprlock.useWallpaper = false;
    programs = {
      waybar.systemd.enable = true;
      hyprlock = {
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
      hyprshell = {
        enable = true;
        systemd.args = "-v";
        settings = {
          windows = {
            switch = {
              enable = true;
              modifier = "super";
            };
          };
        };
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
            timeout = 300;
            on-timeout = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
            on-resume = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
          }
          {
            timeout = 330;
            on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
          }

          {
            timeout = 1800;
            on-timeout = "${pkgs.systemd}/bin/systemctl suspend";
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

        monitor = builtins.concatLists (builtins.map (
            {
              res,
              pos,
              name,
              transform,
              refresh_rate,
              ...
            }: let
              r = "${builtins.toString res.width}x${builtins.toString res.height}";
              p = "${builtins.toString pos.x}x${builtins.toString pos.y}";
              t = builtins.toString (transform / 90);
              rr =
                if builtins.isNull refresh_rate
                then r
                else "${r}@${builtins.toString refresh_rate}";
            in [
              "desc:${name}, ${rr}, ${p}, 1, transform, ${t}"
            ]
          )
          cfg.monitors);

        workspace =
          builtins.map (
            {
              port,
              workspace,
              ...
            }: "${builtins.toString workspace}, monitor:${port}"
          )
          cfg.monitors;

        bindm = [
          "${mod}, mouse:272, movewindow"
          "${mod}, mouse:273, resizewindow"
        ];

        windowrule =
          [
            #"tile, class:.*"
            "suppressevent maximize, class:.*"
            "nomaxsize, class:.*"
          ]
          ++ builtins.map (title: "tile, title:${title}") [
            "MTGA"
            "Monster Train 2"
            "MonsterTrain2"
          ];

        bind =
          [
            "${mod}, Q, killactive,"
            "${mod}, S, togglegroup"
            "${mod}, escape, exec, ${pkgs.systemd}/bin/loginctl lock-session"
            "${mod} SHIFT, escape, exec, ${pkgs.systemd}/bin/loginctl terminate-session self"
            "${mod}, T, exec, ${pkgs.rio}/bin/rio"
            "${mod}, D, exec, ${pkgs.tofi}/bin/tofi-drun | xargs ${pkgs.hyprland}/bin/hyprctl dispatch exec --"
            "${mod}, mouse_down, workspace, e+1"
            "${mod}, mouse_up, workspace, e-1"
            "${mod}, G, togglefloating,"
            "${mod}, Y, changegroupactive, f"
            "${mod}, O, changegroupactive, b"
            "${mod}, F, fullscreen, 1"
            "${mod} SHIFT, F, fullscreen, 0"
            ", Print, exec, ${pkgs.sway-contrib.grimshot}/bin/grimshot --notify copy area"
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
