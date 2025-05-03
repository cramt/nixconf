{
  config,
  pkgs,
  lib,
  ...
}: let
  # for now just use sway's config stuff
  cfg = config.myHomeManager.sway;
  screenSpecificVideos =
    builtins.mapAttrs
    (
      name: value: let
        res = "${toString value.res.width}:${toString value.res.height}";
        rotation = lib.concatMapStrings (_: ",transpose=2") (lib.range 1 (value.transform / 90));
      in (pkgs.runCommand "screen_specific_videos" {} ''
        mkdir -p $out

        ${pkgs.ffmpeg}/bin/ffmpeg -i ${cfg.backgroundVideo} -filter:v "scale=${res}:force_original_aspect_ratio=increase,crop=${res}${rotation}" $out/output.mp4
      '')
    )
    cfg.monitors;
  setBackground = pkgs.writeShellScriptBin "set_background" ''
    pkill mpvpaper
    ${lib.strings.concatStringsSep "\n" (lib.attrsets.mapAttrsToList (
        name: value: "${pkgs.mpvpaper}/bin/mpvpaper -o \"--loop\" -f '${name}' ${value}/output.mp4"
      )
      screenSpecificVideos)}
    sleep 1
  '';
in {
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
      panels = [
        {
          name = "Panel";
          expand_to_edges = false;
          anchor = config.lib.cosmic.mkRON "enum" "Bottom";
          opacity = 0.8;
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
