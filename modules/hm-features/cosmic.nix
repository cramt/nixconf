{ ... }: {
  hmModules.features.cosmic = { config, lib, pkgs, ... }:
  let
    ron = config.lib.cosmic.mkRON;
  in {
    options.myHomeManager.cosmic.enable = lib.mkEnableOption "myHomeManager.cosmic";
    config = lib.mkIf config.myHomeManager.cosmic.enable {
      xdg = {
        portal = {
          enable = true;
          xdgOpenUsePortal = false;
          extraPortals = [ pkgs.xdg-desktop-portal-cosmic pkgs.xdg-desktop-portal-gtk ];
          config.common = {
            default = [ "cosmic" ];
            "org.freedesktop.portal.OpenURI" = [ "gtk" ];
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
        wallpapers = [{
          output = "all";
          source = ron "enum" {
            variant = "Path";
            value = [ config.stylix.image ];
          };
          filter_by_theme = true;
          filter_method = ron "enum" "Lanczos";
          scaling_mode = ron "enum" "Zoom";
          sampling_method = ron "enum" "Alphanumeric";
          rotation_frequency = 300;
        }];
        panels = [
          {
            name = "Panel";
            anchor = ron "enum" "Left";
            anchor_gap = false;
            autohide = null;
            background = ron "enum" "ThemeDefault";
            border_radius = 160;
            expand_to_edges = false;
            keyboard_interactivity = ron "enum" "OnDemand";
            layer = ron "enum" "Top";
            margin = 0;
            opacity = 0.8;
            output = ron "enum" "All";
            padding = 0;
            padding_overlap = 0.5;
            size = ron "enum" "XS";
            size_center = ron "optional" null;
            size_wings = ron "optional" null;
            spacing = 0;
            exclusive_zone = true;
            autohover_delay_ms = ron "optional" 500;
            plugins_center = ron "optional" [ "com.system76.CosmicAppletTime" ];
            plugins_wings = ron "optional" (ron "tuple" [
              [
                "com.system76.CosmicPanelWorkspacesButton"
                "com.system76.CosmicPanelAppButton"
              ]
              [
                "com.system76.CosmicAppletStatusArea"
                "com.system76.CosmicAppletTiling"
                "com.system76.CosmicAppletAudio"
                "com.system76.CosmicAppletNetwork"
                "com.system76.CosmicAppletBattery"
                "com.system76.CosmicAppletNotifications"
                "com.system76.CosmicAppletBluetooth"
                "com.system76.CosmicAppletPower"
              ]
            ]);
          }
        ];
        shortcuts = [
          { action = ron "enum" "Disable"; key = "Super+y"; }
          { action = ron "enum" "Disable"; key = "Super+slash"; }
          { action = ron "enum" "Disable"; key = "Super+f"; }
          { action = ron "enum" "Disable"; key = "Super+b"; }
          { action = ron "enum" { value = [ "${pkgs.ghostty}/bin/ghostty" ]; variant = "Spawn"; }; key = "Super+t"; }
          { action = ron "enum" { value = [ (ron "enum" "PlayPause") ]; variant = "System"; }; key = "Super+Shift+space"; }
        ];
        appearance = {
          theme.dark.gaps = ron "tuple" [ 0 1 ];
          toolkit = {
            interface_font = {
              family = "Iosevka Nerd Font";
              stretch = ron "enum" "Normal";
              style = ron "enum" "Normal";
              weight = ron "enum" "Normal";
            };
            monospace_font = {
              family = "Iosevka Nerd Font Mono";
              stretch = ron "enum" "Normal";
              style = ron "enum" "Normal";
              weight = ron "enum" "Normal";
            };
            show_minimize = false;
            header_size = ron "enum" "Compact";
            interface_density = ron "enum" "Compact";
          };
        };
        compositor = {
          autotile = true;
          cursor_follows_focus = true;
          focus_follows_cursor = true;
          focus_follows_cursor_delay = 100;
          autotile_behavior = ron "enum" "PerWorkspace";
          xkb_config = {
            rules = "";
            model = "pc104";
            layout = "dk";
            variant = "nodeadkeys";
            options = ron "optional" "terminate:ctrl_alt_bksp";
            repeat_delay = 600;
            repeat_rate = 25;
          };
          input_default = {
            state = ron "enum" "Enabled";
            acceleration = ron "optional" {
              profile = ron "optional" (ron "enum" "Flat");
              speed = 0.6042271248762552;
            };
          };
        };
      };
    };
  };
}
