# Noctalia — Quickshell-based Wayland shell (bar, launcher, control center,
# notifications, lock screen, media/volume/brightness OSD).
#
# Compositor-agnostic: it only needs the wlr-layer-shell protocol, which niri,
# cosmic-comp, Hyprland, sway, etc. all provide, so this feature is shared by
# whatever compositor feature wants it (see modules/hm-features/niri.nix and
# modules/hm-features/cosmic.nix, which set myHomeManager.noctalia.enable).
#
# Workspace / active-window widgets use native IPC on niri & Hyprland and fall
# back to the ext-workspace-v1 protocol elsewhere (e.g. COSMIC), where that
# integration is reduced.
#
# Keybinds are NOT defined here — they are compositor-specific. The shell drives
# everything over `noctalia-shell ipc call <target> <fn>`; wire keys to that
# from the compositor feature. The one reusable, compositor-agnostic helper
# (the bar display-mode toggle) is exposed as a read-only option below.
{ ... }: {
  hmModules.features.noctalia = { config, lib, pkgs, ... }: let
    cfg = config.myHomeManager.noctalia;

    noctaliaExe = lib.getExe pkgs.noctalia-shell;

    # quickshell's path/config-based `ipc` lookup does NOT match our instance
    # when it's launched as a systemd service with `-p <store-dir>`: it reports
    # "No running instances" even with exactly one live instance and a correct
    # by-path registry entry. Targeting the live process by pid works reliably.
    # This wrapper resolves the pid from the service on each call (so it survives
    # noctalia restarts) and forwards the ipc args, e.g. `call launcher toggle`.
    noctaliaIpc = pkgs.writeShellScript "noctalia-ipc" ''
      pid=$(${pkgs.systemd}/bin/systemctl --user show -p MainPID --value noctalia.service 2>/dev/null)
      if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        exec ${noctaliaExe} ipc --pid "$pid" "$@"
      fi
      # Fallback to the default lookup if the service isn't found.
      exec ${noctaliaExe} ipc "$@"
    '';

    # Map the active stylix base16 palette onto noctalia's Material-style color
    # scheme so the shell matches the rest of the system theme. Stylix is dark,
    # so we point noctalia at this scheme with darkMode on; both dark/light
    # variants are filled with the same colors as a safe fallback.
    c = config.lib.stylix.colors.withHashtag;
    stylixVariant = {
      mPrimary = c.base0D;
      mOnPrimary = c.base00;
      mSecondary = c.base09;
      mOnSecondary = c.base00;
      mTertiary = c.base0C;
      mOnTertiary = c.base00;
      mError = c.base08;
      mOnError = c.base00;
      mSurface = c.base00;
      mOnSurface = c.base05;
      mSurfaceVariant = c.base01;
      mOnSurfaceVariant = c.base04;
      mOutline = c.base03;
      mShadow = c.base00;
      mHover = c.base0D;
      mOnHover = c.base00;
      terminal = {
        normal = { black = c.base00; red = c.base08; green = c.base0B; yellow = c.base0A; blue = c.base0D; magenta = c.base0E; cyan = c.base0C; white = c.base05; };
        bright = { black = c.base03; red = c.base08; green = c.base0B; yellow = c.base0A; blue = c.base0D; magenta = c.base0E; cyan = c.base0C; white = c.base07; };
        foreground = c.base05;
        background = c.base00;
        selectionFg = c.base00;
        selectionBg = c.base05;
        cursorText = c.base00;
        cursor = c.base05;
      };
    };
    stylixScheme = { dark = stylixVariant; light = stylixVariant; };

    # noctalia's ~/.config/noctalia/settings.json. Kept as a binding so it can be
    # referenced both by xdg.configFile and as a restart trigger on the noctalia
    # systemd user service (so `nh os switch` restarts the shell on a change).
    # We manage only the keys we care about; the rest fall back to its defaults.
    noctaliaSettings = (pkgs.formats.json {}).generate "noctalia-settings.json" {
      bar.position = "left";
      # Default to always-visible (working). Super+Shift+B toggles to auto_hide
      # (hidden, reveals on hover) for gaming — see barModeToggle below.
      bar.displayMode = "always_visible";
      # No bottom dock — the left bar already covers launching/window nav.
      dock.enabled = false;
      # Declaring bar.widgets fully replaces noctalia's built-in default
      # layout (it is not merged), so the defaults are replicated here with
      # a Bluetooth widget added to the bottom cluster (right = bottom on a
      # left/vertical bar). Per-widget settings fall back to the registry
      # defaults; only the id is needed to place a widget.
      bar.widgets = {
        left = [
          { id = "Launcher"; }
          { id = "Clock"; }
          { id = "SystemMonitor"; }
          { id = "ActiveWindow"; }
          { id = "MediaMini"; }
        ];
        center = [
          { id = "Workspace"; }
        ];
        # NotificationHistory only makes sense when noctalia is the notification
        # daemon — drop it when another shell (e.g. COSMIC) owns notifications.
        right = [
          { id = "Tray"; }
        ] ++ lib.optional cfg.notifications.enable { id = "NotificationHistory"; } ++ [
          { id = "Battery"; }
          { id = "Volume"; }
          { id = "Brightness"; }
          { id = "Bluetooth"; }
          { id = "ControlCenter"; }
        ];
      };
      # enabled = false stops noctalia from claiming org.freedesktop.Notifications
      # (NotificationService.qml gates the server on this), so another daemon can
      # own notifications without a D-Bus name fight. Otherwise: calmer toasts —
      # bottom-right instead of top-right, compact density (320px vs 440px), a
      # touch of transparency, and a shorter normal-urgency lifetime (5s vs 8s).
      notifications = {
        enabled = cfg.notifications.enable;
        location = "bottom_right";
        density = "compact";
        backgroundOpacity = 0.92;
        normalUrgencyDuration = 5;
      };
      colorSchemes = {
        useWallpaperColors = false;
        predefinedScheme = "Stylix";
        darkMode = true;
      };
      # We paint the wallpaper with swaybg (stylix image) instead of letting
      # noctalia show its bundled default.
      wallpaper.enabled = false;
    };

    # Toggle the bar between "always visible" (default, good for working) and
    # "auto_hide" (hidden, reveals on hover at the edge — good for gaming, where
    # on saturn's ultrawide the game is windowed, not fullscreen, so it can't be
    # detected via fullscreen state). noctalia has no mode-toggle IPC, only
    # `bar setDisplayMode <mode>`, and our settings.json is a read-only nix store
    # symlink so noctalia can't persist a runtime mode change — so we track the
    # current mode in a runtime-dir state file and flip it ourselves.
    barModeToggle = pkgs.writeShellScript "noctalia-bar-mode-toggle" ''
      state="''${XDG_RUNTIME_DIR:-/tmp}/noctalia-bar-mode"
      if [ "$(${pkgs.coreutils}/bin/cat "$state" 2>/dev/null)" = "auto_hide" ]; then
        next=always_visible
      else
        next=auto_hide
      fi
      ${pkgs.coreutils}/bin/echo "$next" > "$state"
      exec ${noctaliaIpc} call bar setDisplayMode "$next" all
    '';
  in {
    options.myHomeManager.noctalia = {
      enable = lib.mkEnableOption "myHomeManager.noctalia";

      # Whether noctalia acts as the org.freedesktop.Notifications daemon. Set
      # false to hand notifications to another shell (e.g. COSMIC's own daemon)
      # and avoid both fighting over the D-Bus name. NOTE: settings.json is a
      # single file shared by every wayland session, so this is global — turning
      # it off also disables noctalia notifications under niri.
      notifications.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether noctalia owns notifications (the freedesktop notification daemon).";
      };

      # Read-only handles so compositor features can wire keybinds without
      # re-deriving these scripts.
      ipc = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        description = "Wrapper that forwards `ipc` args to the live noctalia instance (by pid).";
      };
      barModeToggle = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        description = "Script toggling the bar between always_visible and auto_hide.";
      };
    };

    config = lib.mkIf cfg.enable {
      myHomeManager.noctalia.ipc = noctaliaIpc;
      myHomeManager.noctalia.barModeToggle = barModeToggle;

      # Enables the package + the homeModule wiring. We leave its own
      # systemd.enable off (default) and run our own unit below so we can
      # attach X-Restart-Triggers for settings.json.
      programs.noctalia = {
        enable = true;
        package = pkgs.noctalia-shell;
      };

      # Run noctalia as a user service anchored to graphical-session.target, so
      # it comes up in ANY wayland session (niri or COSMIC). Because it's a
      # managed unit, `nh os switch` (home-manager's sd-switch) restarts it on
      # any change — including the X-Restart-Triggers below, which fire whenever
      # settings.json changes. No more manual restart.
      systemd.user.services.noctalia = {
        Unit = {
          Description = "Noctalia shell";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          X-Restart-Triggers = [ "${noctaliaSettings}" ];
        };
        Service = {
          ExecStart = noctaliaExe;
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # noctalia 4.7.x reads ~/.config/noctalia/settings.json. The homeModule's
      # `settings` option instead writes a v5-style config.toml that 4.7 ignores,
      # so we write settings.json ourselves. noctalia is built to handle a
      # symlinked/read-only settings.json (it reloads on store-path swap); we
      # manage only the keys we care about, the rest fall back to its defaults.
      xdg.configFile = {
        "noctalia/settings.json".source = noctaliaSettings;
        # The custom scheme that predefinedScheme = "Stylix" resolves to.
        # noctalia loads schemes from ~/.config/noctalia/colorschemes/<name>/<name>.json.
        "noctalia/colorschemes/Stylix/Stylix.json".source =
          (pkgs.formats.json {}).generate "Stylix.json" stylixScheme;
      };
    };
  };
}
