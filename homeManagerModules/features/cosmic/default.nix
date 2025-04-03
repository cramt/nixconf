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
