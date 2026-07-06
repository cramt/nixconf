{ ... }: {
  hmModules.features.cosmic = { config, lib, pkgs, ... }:
  let
    ron = config.lib.cosmic.mkRON;

    # COSMIC's Spawn action takes a single command string (cosmic-comp
    # shlex-splits it into argv), so build one string rather than an argv list.
    spawn = key: cmd: {
      inherit key;
      action = ron "enum" { variant = "Spawn"; value = [ cmd ]; };
    };
    # A Spawn shortcut driving a noctalia v5 IPC action: `noctalia msg <command>`
    # (cosmic-comp shlex-splits the string into argv). v5 talks to the single
    # live instance over its unix socket — no pid/path juggling.
    noctaliaMsg = key: cmd:
      spawn key "${config.myHomeManager.noctalia.cli} msg ${cmd}";
  in {
    options.myHomeManager.cosmic.enable = lib.mkEnableOption "myHomeManager.cosmic";
    config = lib.mkIf config.myHomeManager.cosmic.enable {
      # Use noctalia as the shell instead of COSMIC's own panel/dock + applets
      # (stripped below). noctalia draws over cosmic-comp's wlr-layer-shell; its
      # systemd unit is anchored to graphical-session.target, which the COSMIC
      # session activates, so it starts automatically here.
      myHomeManager.noctalia.enable = true;
      # Let COSMIC's own daemon own notifications under COSMIC; stop noctalia
      # from claiming the freedesktop notification name so they don't fight.
      # (settings.json is shared across sessions, so this also turns off noctalia
      # notifications under niri — COSMIC isn't running there to pick them up.)
      myHomeManager.noctalia.notifications.enable = false;

      xdg = {
        portal = {
          enable = true;
          xdgOpenUsePortal = false;
          extraPortals = [ pkgs.xdg-desktop-portal-cosmic pkgs.xdg-desktop-portal-gtk ];
          # Scope this to the COSMIC session only (writes cosmic-portals.conf,
          # not the session-agnostic portals.conf). xdg-desktop-portal lower-
          # cases XDG_CURRENT_DESKTOP, so a COSMIC session matches "cosmic".
          #
          # Previously this was config.common, which writes ~/.config/xdg-
          # desktop-portal/portals.conf and applies to EVERY session. In the
          # niri session that file (a) shadowed /etc/xdg/.../niri-portals.conf
          # and (b) routed all portal interfaces to the cosmic backend, which
          # cannot activate outside COSMIC — so every portal call (incl. the
          # Settings reads GTK apps make on startup) blocked ~1.3s on cosmic's
          # D-Bus activation timeout, making ghostty et al. spawn slowly.
          config.cosmic = {
            default = [ "cosmic" ];
            "org.freedesktop.portal.OpenURI" = [ "gtk" ];
          };
        };
      };
      wayland.desktopManager.cosmic = {
        enable = true;
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
        # No COSMIC panel or dock — noctalia is the shell (enabled above). This
        # writes com.system76.CosmicPanel.entries.entries = [], which removes
        # both the default Panel and Dock (in cosmic-manager both are just
        # entries in this one list). The status/notification/power/etc. applets
        # that used to live here are now owned by noctalia.
        panels = [ ];
        shortcuts = [
          { action = ron "enum" "Disable"; key = "Super+y"; }
          { action = ron "enum" "Disable"; key = "Super+slash"; }
          { action = ron "enum" "Disable"; key = "Super+f"; }
          { action = ron "enum" { value = [ "${pkgs.ghostty}/bin/ghostty" ]; variant = "Spawn"; }; key = "Super+t"; }
          { action = ron "enum" { value = [ (ron "enum" "PlayPause") ]; variant = "System"; }; key = "Super+Shift+space"; }

          # noctalia shell — launcher / panels / session. Mirrors the niri binds
          # (modules/hm-features/niri.nix) so the shell feels the same in both
          # sessions. Window management, volume/brightness/media stay native to
          # COSMIC (it has its own OSD + handling).
          (noctaliaMsg "Super+d" "panel-toggle launcher")
          (noctaliaMsg "Super+v" "panel-toggle clipboard")
          (noctaliaMsg "Super+period" "panel-toggle launcher emoji")
          (noctaliaMsg "Super+c" "panel-toggle control-center")
          (noctaliaMsg "Super+b" "bar-toggle")
          (spawn "Super+Shift+b" "${config.myHomeManager.noctalia.barModeToggle}")
          # Super+Escape locks via COSMIC's own lock screen (cosmic-greeter),
          # not noctalia's session panel — COSMIC owns the session here.
          { action = ron "enum" { value = [ (ron "enum" "LockScreen") ]; variant = "System"; }; key = "Super+Escape"; }
          (noctaliaMsg "Super+F1" "session lock")
        ];
        appearance = {
          theme.dark.gaps = ron "tuple" [ 0 1 ];
          # The active-window highlight ("active hint") is drawn in the theme
          # accent. COSMIC's default accent is blue and is NOT stylix-aware, so
          # without this it stays blue and only survives as runtime state under
          # ~/.config/cosmic (wiped on reinstall). Pin it to base0D — the same
          # color niri uses for its focus border (#8b8683 in this scheme) — and
          # match niri's 1px width, so the highlight is consistent across
          # sessions and fully declarative.
          theme.dark.accent =
            let c = config.lib.stylix.colors;
            in ron "optional" {
              red = builtins.fromJSON c."base0D-dec-r";
              green = builtins.fromJSON c."base0D-dec-g";
              blue = builtins.fromJSON c."base0D-dec-b";
            };
          theme.dark.active_hint = 1;
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
              # Pass as raw RON so the exact value is emitted verbatim; a bare
              # Nix float loses precision on float→string conversion (warns
              # "Imprecise conversion from float to string").
              speed = ron "raw" "0.6042271248762552";
            };
          };
        };
      };
    };
  };
}
