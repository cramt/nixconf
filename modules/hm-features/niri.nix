# Niri (scrollable-tiling Wayland compositor) — the user-side config.
#
# Pairs with the NixOS module modules/desktop/niri.nix (myNixOS.niri), which
# registers the session and sets up portals/polkit/keyring. The shell
# (bar/launcher/control-center/lock/OSD) is noctalia, now a standalone feature
# (modules/hm-features/noctalia.nix); this feature just enables it and routes
# keybinds to its IPC.
#
# Keybinds mirror conventions used elsewhere in this config: Super modifier,
# ghostty terminal on Super+Return, Super+Q to close, Super+D launcher (sway's
# menu bind), Super+F1 lock, print-screen screenshots, and volume/brightness/
# media routed through noctalia's IPC so its on-screen OSD shows.
{ ... }: {
  hmModules.features.niri = { config, lib, pkgs, ... }: let
    cfg = config.myHomeManager;

    ghostty = lib.getExe pkgs.ghostty;

    # noctalia IPC action: forwards `call <target> <function>` to the live
    # noctalia instance via the shared pid-resolving wrapper (path-based
    # quickshell ipc lookup is unreliable — see modules/hm-features/noctalia.nix).
    # Returns a niri action attrset (spawn argv list — no shell needed).
    ipc = target: fn: { spawn = [ "${cfg.noctalia.ipc}" "call" target fn ]; };

    # Per-host monitor layout (see hosts/<name>/monitors.nix), keyed by
    # connector (port) the same way the kernel video= params are.
    outputs = builtins.listToAttrs (builtins.map (
      { port, res, pos, transform, refresh_rate, ... }: {
        name = port;
        value = {
          mode = {
            width = res.width;
            height = res.height;
          } // lib.optionalAttrs (refresh_rate != null) { refresh = refresh_rate; };
          position = { x = pos.x; y = pos.y; };
          transform.rotation = transform;
        };
      }
    ) cfg.monitors);

    # Super+1..9 → focus workspace N, Super+Shift+1..9 → move column to N.
    workspaceBinds = builtins.listToAttrs (builtins.concatMap (n: [
      { name = "Mod+${toString n}"; value.action.focus-workspace = n; }
      { name = "Mod+Shift+${toString n}"; value.action.move-column-to-workspace = n; }
    ]) (lib.range 1 9));

    mainBinds = {
      # Apps / launcher
      "Mod+Return".action.spawn = ghostty;
      "Mod+T".action.spawn = ghostty;            # COSMIC's terminal bind
      "Mod+D".action = ipc "launcher" "toggle";
      "Mod+V".action = ipc "launcher" "clipboard";
      "Mod+Period".action = ipc "launcher" "emoji";
      "Mod+Q".action.close-window = [];

      # noctalia panels
      "Mod+C".action = ipc "controlCenter" "toggle";
      "Mod+N".action = ipc "notifications" "toggleHistory";
      "Mod+B".action = ipc "bar" "toggle";
      # Toggle bar auto-hide on/off (always-visible ⇆ hide-except-on-hover).
      "Mod+Shift+B".action.spawn = "${cfg.noctalia.barModeToggle}";
      "Mod+Escape".action = ipc "sessionMenu" "toggle";
      "Mod+F1".action = ipc "lockScreen" "lock";

      # Focus (column = horizontal, window = vertical within a column)
      "Mod+H".action.focus-column-left = [];
      "Mod+L".action.focus-column-right = [];
      "Mod+J".action.focus-window-down = [];
      "Mod+K".action.focus-window-up = [];
      "Mod+Left".action.focus-column-left = [];
      "Mod+Right".action.focus-column-right = [];
      "Mod+Down".action.focus-window-down = [];
      "Mod+Up".action.focus-window-up = [];

      # Move
      "Mod+Shift+H".action.move-column-left = [];
      "Mod+Shift+L".action.move-column-right = [];
      "Mod+Shift+J".action.move-window-down = [];
      "Mod+Shift+K".action.move-window-up = [];
      "Mod+Shift+Left".action.move-column-left = [];
      "Mod+Shift+Right".action.move-column-right = [];
      "Mod+Shift+Down".action.move-window-down = [];
      "Mod+Shift+Up".action.move-window-up = [];

      # Focus another monitor (vim keys, by logical position)
      "Mod+Ctrl+H".action.focus-monitor-left = [];
      "Mod+Ctrl+L".action.focus-monitor-right = [];
      "Mod+Ctrl+K".action.focus-monitor-up = [];
      "Mod+Ctrl+J".action.focus-monitor-down = [];

      # Move column to another monitor (COSMIC "move to display")
      "Mod+Ctrl+Left".action.move-column-to-monitor-left = [];
      "Mod+Ctrl+Right".action.move-column-to-monitor-right = [];
      "Mod+Ctrl+Up".action.move-column-to-monitor-up = [];
      "Mod+Ctrl+Down".action.move-column-to-monitor-down = [];

      # Vertical workspace navigation
      "Mod+Page_Down".action.focus-workspace-down = [];
      "Mod+Page_Up".action.focus-workspace-up = [];
      "Mod+Shift+Page_Down".action.move-workspace-down = [];
      "Mod+Shift+Page_Up".action.move-workspace-up = [];

      # Column / window sizing & layout
      "Mod+R".action.switch-preset-column-width = [];
      "Mod+F".action.maximize-column = [];
      "Mod+Shift+F".action.fullscreen-window = [];
      "Mod+Shift+C".action.center-column = [];
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";
      "Mod+BracketLeft".action.consume-or-expel-window-left = [];
      "Mod+BracketRight".action.consume-or-expel-window-right = [];

      # Floating
      "Mod+Space".action.switch-focus-between-floating-and-tiling = [];
      "Mod+W".action.toggle-window-floating = [];

      # Overview (niri's window switcher / overview)
      "Mod+Tab".action.toggle-overview = [];

      # Screenshots (niri built-in: saves + copies)
      "Print".action.screenshot = [];
      "Mod+Print".action.screenshot-screen = [];
      "Shift+Print".action.screenshot-window = [];

      # Session
      "Mod+Shift+E".action.quit = [];

      # Media / volume / brightness → noctalia OSD
      "XF86AudioRaiseVolume" = { action = ipc "volume" "increase"; allow-when-locked = true; };
      "XF86AudioLowerVolume" = { action = ipc "volume" "decrease"; allow-when-locked = true; };
      "XF86AudioMute" = { action = ipc "volume" "muteOutput"; allow-when-locked = true; };
      "XF86AudioMicMute" = { action = ipc "volume" "muteInput"; allow-when-locked = true; };
      "Mod+Z".action = ipc "volume" "muteInput";
      "XF86MonBrightnessUp".action = ipc "brightness" "increase";
      "XF86MonBrightnessDown".action = ipc "brightness" "decrease";
      "XF86AudioPlay" = { action = ipc "media" "playPause"; allow-when-locked = true; };
      "XF86AudioNext" = { action = ipc "media" "next"; allow-when-locked = true; };
      "XF86AudioPrev" = { action = ipc "media" "previous"; allow-when-locked = true; };
      "Mod+Shift+Return".action = ipc "media" "playPause";
      "Mod+Shift+Space".action = ipc "media" "playPause";   # COSMIC's play/pause bind
    };
  in {
    options.myHomeManager.niri.enable = lib.mkEnableOption "myHomeManager.niri";

    config = lib.mkIf config.myHomeManager.niri.enable {
      # Shell: bar, launcher, notifications, control center, lock, OSD. Now a
      # standalone, compositor-agnostic feature (its systemd unit is anchored to
      # graphical-session.target). The niri keybinds below drive it over IPC.
      myHomeManager.noctalia.enable = true;

      programs.niri.settings = {
        prefer-no-csd = true;

        # noctalia itself is started by its own systemd user service (see
        # modules/hm-features/noctalia.nix), not from here. We still paint the
        # stylix wallpaper with swaybg (noctalia's own wallpaper module is
        # disabled, so it would otherwise show its bundled default).
        spawn-at-startup = [
          { argv = [ (lib.getExe pkgs.swaybg) "-i" "${config.stylix.image}" "-m" "fill" ]; }
        ];

        # Integrated XWayland: niri spawns xwayland-satellite and manages DISPLAY
        # for spawned clients itself — the part that's painful to wire by hand.
        xwayland-satellite = {
          enable = true;
          path = lib.getExe pkgs.xwayland-satellite-stable;
        };

        input = {
          keyboard.xkb = {
            layout = "dk";
            variant = "nodeadkeys";
          };
          touchpad = {
            tap = true;
            natural-scroll = false;
          };
          # Match COSMIC's focus_follows_cursor.
          focus-follows-mouse.enable = true;
        };

        inherit outputs;

        # The window focus highlight (and cursor) are themed by niri-flake's
        # stylix module: it enables a stylix-colored *border* (active = base0D,
        # inactive = base03) and disables the focus-ring. Previously we forced
        # the focus-ring on with no color, which is where the default blue ring
        # came from. Only set gaps here and let stylix own the highlight colors.
        layout = {
          gaps = 0;
          # Thinner focus highlight. stylix sets the border colors + enables it;
          # only the width is left at niri's default (4), so override just that.
          border.width = 1;
          # Widths cycled by Super+R (switch-preset-column-width). Includes a
          # full-width option so a column can fill the working area (= monitor
          # minus the bar). Super+F (maximize-column) also snaps to full instantly.
          preset-column-widths = [
            { proportion = 1. / 3.; }
            { proportion = 1. / 2.; }
            { proportion = 2. / 3.; }
            { proportion = 1.; }
          ];
        };

        # Open browsers maximized (full working-area width, i.e. monitor minus
        # the bar). Regex is case-insensitive and substring-matched, so it
        # catches helium/firefox/zen whatever their exact app-id. Check an app's
        # id with `niri msg windows` if you want to add more.
        window-rules = [
          {
            matches = [ { app-id = "(?i)(helium|firefox|zen)"; } ];
            open-maximized = true;
          }
        ];

        hotkey-overlay.skip-at-startup = true;

        binds = mainBinds // workspaceBinds;
      };
    };
  };
}
