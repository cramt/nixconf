# Niri (scrollable-tiling Wayland compositor) + noctalia (shell/bar/launcher/
# control-center/lock) — the user-side config.
#
# Pairs with the NixOS module modules/desktop/niri.nix (myNixOS.niri), which
# registers the session and sets up portals/polkit/keyring. Enabling
# myHomeManager.niri also brings up noctalia as a systemd user service bound to
# the graphical session.
#
# Keybinds mirror conventions used elsewhere in this config: Super modifier,
# ghostty terminal on Super+Return, Super+Q to close, Super+D launcher (sway's
# menu bind), Super+F1 lock, print-screen screenshots, and volume/brightness/
# media routed through noctalia's IPC so its on-screen OSD shows.
{ ... }: {
  hmModules.features.niri = { config, lib, pkgs, ... }: let
    cfg = config.myHomeManager;

    ghostty = lib.getExe pkgs.ghostty;
    noctalia = lib.getExe pkgs.noctalia-shell;

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

    # Restart the noctalia shell (e.g. after a config change). noctalia-shell is
    # a launcher that execs into quickshell, so we match the full command line.
    # The script is deliberately named without "noctalia-shell" so the pkill
    # can't match (and kill) this very process.
    restartNoctalia = pkgs.writeShellScript "restart-shell" ''
      ${pkgs.procps}/bin/pkill -f noctalia-shell 2>/dev/null || true
      ${pkgs.coreutils}/bin/sleep 0.3
      exec ${noctalia}
    '';

    # noctalia IPC action: `noctalia-shell ipc call <target> <function>`.
    # Returns a niri action attrset (spawn argv list — no shell needed).
    ipc = target: fn: { spawn = [ noctalia "ipc" "call" target fn ]; };

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
      "Ctrl+T".action.spawn = ghostty;
      "Mod+T".action.spawn = ghostty;            # COSMIC's terminal bind
      "Mod+D".action = ipc "launcher" "toggle";
      "Mod+V".action = ipc "launcher" "clipboard";
      "Mod+Period".action = ipc "launcher" "emoji";
      "Mod+Q".action.close-window = [];

      # noctalia panels
      "Mod+C".action = ipc "controlCenter" "toggle";
      "Mod+N".action = ipc "notifications" "toggleHistory";
      "Mod+Shift+N".action.spawn = "${restartNoctalia}";   # restart the noctalia shell
      "Mod+B".action = ipc "bar" "toggle";
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
      # Shell: bar, launcher, notifications, control center, lock, wallpaper.
      # NOT systemd.enable — that binds to graphical-session.target, which COSMIC
      # also activates, so noctalia would leak onto the COSMIC session. Instead we
      # spawn it from niri (spawn-at-startup below) so it's scoped to niri only.
      programs.noctalia = {
        enable = true;
        package = pkgs.noctalia-shell;
      };

      # noctalia 4.7.x reads ~/.config/noctalia/settings.json. The homeModule's
      # `settings` option instead writes a v5-style config.toml that 4.7 ignores,
      # so we write settings.json ourselves. noctalia is built to handle a
      # symlinked/read-only settings.json (it reloads on store-path swap); we
      # manage only the keys we care about, the rest fall back to its defaults.
      xdg.configFile = {
        "noctalia/settings.json".source = (pkgs.formats.json {}).generate "noctalia-settings.json" {
          bar.position = "left";
          colorSchemes = {
            useWallpaperColors = false;
            predefinedScheme = "Stylix";
            darkMode = true;
          };
          # We paint the wallpaper with swaybg (stylix image) instead of letting
          # noctalia show its bundled default.
          wallpaper.enabled = false;
        };
        # The custom scheme that predefinedScheme = "Stylix" resolves to.
        # noctalia loads schemes from ~/.config/noctalia/colorschemes/<name>/<name>.json.
        "noctalia/colorschemes/Stylix/Stylix.json".source =
          (pkgs.formats.json {}).generate "Stylix.json" stylixScheme;
      };

      programs.niri.settings = {
        prefer-no-csd = true;

        # Start the noctalia shell with niri (and only with niri). niri puts this
        # in a transient systemd scope, so an OOM here won't take down the session.
        spawn-at-startup = [
          { argv = [ noctalia ]; }
          # noctalia's own wallpaper module is disabled (it paints its bundled
          # default otherwise — see settings below), so paint the stylix
          # wallpaper ourselves with swaybg.
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
        layout.gaps = 5;

        hotkey-overlay.skip-at-startup = true;

        binds = mainBinds // workspaceBinds;
      };
    };
  };
}
