{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.myHomeManager;
in {
  options.myHomeManager.hyprland = {
    exec = lib.mkOption {
      type = lib.types.str;
      description = "Command to run in kiosk mode";
      example = "firefox --kiosk https://grafana.example.com";
    };
  };

  config = {
    wayland.windowManager.hyprland = {
      enable = true;
      settings = {
        exec-once = cfg.hyprland.exec;

        general = {
          gaps_in = 0;
          gaps_out = 0;
          border_size = 0;
        };

        decoration = {
          rounding = 0;
          shadow.enabled = false;
          blur.enabled = false;
        };

        animations.enabled = false;

        input = {
          kb_layout = "dk";
        };

        misc = {
          force_default_wallpaper = 0;
          disable_hyprland_logo = true;
        };

        cursor = {
          inactive_timeout = 3;
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

        windowrulev2 = [
          "fullscreen, class:.*"
        ];
      };
    };
  };
}
