{
  config,
  pkgs,
  lib,
  ...
}: {
  config = {
    xdg = {
      portal = {
        enable = true;
        xdgOpenUsePortal = true;
        extraPortals = [pkgs.xdg-desktop-portal-cosmic pkgs.xdg-desktop-portal-gtk];
        config.common = {
          default = ["cosmic"];
          "org.freedesktop.portal.OpenURI" = ["gtk"];
        };
      };
    };
    wayland.desktopManager.cosmic = {
      enable = true;
      applets.time.settings = {
        first_day_of_week = 0;
        military_time = true;
        show_date_in_top_panel = true;
        show_seconds = true;
        show_weekday = true;
      };
      panels = [
        {
          name = "Panel";
          expand_to_edges = false;
          anchor = config.lib.cosmic.mkRON "enum" "Bottom";
          opacity = 0.8;
          margin = 0;
        }
      ];
      shortcuts = [
        {
          action = config.lib.cosmic.mkRON "enum" "Disable";
          key = "Super+y";
        }
        {
          action = config.lib.cosmic.mkRON "enum" "Disable";
          key = "Super+slash";
        }
        {
          action = config.lib.cosmic.mkRON "enum" "Disable";
          key = "Super+f";
        }
        {
          action = config.lib.cosmic.mkRON "enum" "Disable";
          key = "Super+b";
        }
        {
          action = config.lib.cosmic.mkRON "enum" {
            value = [
              "${pkgs.rio}/bin/rio"
            ];
            variant = "Spawn";
          };
          key = "Super+t";
        }
        {
          action = config.lib.cosmic.mkRON "enum" {
            value = [
              (config.lib.cosmic.mkRON "enum" "PlayPause")
            ];
            variant = "System";
          };
          key = "Super+Shift+space";
        }
      ];
      appearance = {
        theme.dark.gaps = config.lib.cosmic.mkRON "tuple" [
          0
          1
        ];
        toolkit = {
          interface_font = {
            family = "Iosevka Nerd Font";
            stretch = config.lib.cosmic.mkRON "enum" "Normal";
            style = config.lib.cosmic.mkRON "enum" "Normal";
            weight = config.lib.cosmic.mkRON "enum" "Normal";
          };
          monospace_font = {
            family = "Iosevka Nerd Font Mono";
            stretch = config.lib.cosmic.mkRON "enum" "Normal";
            style = config.lib.cosmic.mkRON "enum" "Normal";
            weight = config.lib.cosmic.mkRON "enum" "Normal";
          };
          show_minimize = false;
        };
      };
      compositor = {
        autotile = true;
        cursor_follows_focus = true;
        focus_follows_cursor = true;
        focus_follows_cursor_delay = 100;
        autotile_behavior = config.lib.cosmic.mkRON "enum" "PerWorkspace";
      };
    };
  };
}
