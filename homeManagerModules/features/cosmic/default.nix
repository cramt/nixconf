{config, ...}: {
  config = {
    wayland.desktopManager.cosmic = {
      enable = true;
      applets.time.settings = {
        first_day_of_week = 0;
        military_time = true;
        show_date_in_top_panel = true;
        show_seconds = true;
        show_weekday = true;
      };
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
