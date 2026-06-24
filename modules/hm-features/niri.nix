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

    # noctalia's ~/.config/noctalia/settings.json. Kept as a binding so it can be
    # referenced both by xdg.configFile and as a restart trigger on the noctalia
    # systemd user service (so `nh os switch` restarts the shell on a change).
    # We manage only the keys we care about; the rest fall back to its defaults.
    noctaliaSettings = (pkgs.formats.json {}).generate "noctalia-settings.json" {
      bar.position = "left";
      # Default to always-visible (working). Super+Shift+B toggles to auto_hide
      # (hidden, reveals on hover) for gaming — see barModeToggle above.
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
        right = [
          { id = "Tray"; }
          { id = "NotificationHistory"; }
          { id = "Battery"; }
          { id = "Volume"; }
          { id = "Brightness"; }
          { id = "Bluetooth"; }
          { id = "ControlCenter"; }
        ];
      };
      # Calmer, less-invasive notification toasts: bottom-right instead of
      # top-right, compact density (320px wide + tighter layout vs the 440px
      # default), a touch of transparency, and a shorter normal-urgency
      # lifetime (5s vs 8s). Low/critical durations keep their defaults.
      notifications = {
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
      exec ${noctalia} ipc call bar setDisplayMode "$next" all
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
      "Mod+Shift+B".action.spawn = "${barModeToggle}";
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
      # Shell: bar, launcher, notifications, control center, lock, wallpaper.
      # NOT programs.noctalia's own systemd.enable — that unit is WantedBy/
      # PartOf graphical-session.target, which COSMIC also activates, so noctalia
      # would leak onto the COSMIC session. We define our own service below,
      # anchored to niri.service instead (see systemd.user.services.noctalia).
      programs.noctalia = {
        enable = true;
        package = pkgs.noctalia-shell;
      };

      # Run noctalia as a user service anchored to niri.service (niri-flake's
      # compositor unit). niri.service is active only in a niri session and is
      # never started under COSMIC, so this scopes the shell to niri without
      # touching graphical-session.target:
      #   - WantedBy=niri.service  → starts automatically when niri starts
      #   - BindsTo/After=niri.service → stops with niri; starts after it
      #   - After=graphical-session.target → niri has imported WAYLAND_DISPLAY
      #     and the rest of the session env by then
      # Because it's a managed unit, `nh os switch` (home-manager's sd-switch)
      # restarts it on any change — including the X-Restart-Triggers below, which
      # fire it whenever settings.json changes. No more manual Super+Shift+N.
      systemd.user.services.noctalia = {
        Unit = {
          Description = "Noctalia shell (niri session only)";
          PartOf = [ "niri.service" ];
          BindsTo = [ "niri.service" ];
          After = [ "niri.service" "graphical-session.target" ];
          X-Restart-Triggers = [ "${noctaliaSettings}" ];
        };
        Service = {
          ExecStart = noctalia;
          Restart = "on-failure";
        };
        Install.WantedBy = [ "niri.service" ];
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

      programs.niri.settings = {
        prefer-no-csd = true;

        # noctalia itself is started by the noctalia systemd user service (bound
        # to niri.service — see above), not from here. We still paint the stylix
        # wallpaper with swaybg (noctalia's own wallpaper module is disabled, so
        # it would otherwise show its bundled default).
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
