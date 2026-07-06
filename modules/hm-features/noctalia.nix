# Noctalia — Wayland shell (bar, launcher, control center, notifications, lock
# screen, media/volume/brightness OSD).
#
# v5 is a native Wayland+OpenGL-ES rewrite (no longer quickshell). It is fed from
# `pkgs.noctalia` (the flake overlay, see overlays/default.nix) — distinct from
# nixpkgs' older quickshell-based `pkgs.noctalia-shell` (4.7.x). The v5 shell
# avoids the quickshell layer-shell-over-IPC crash that cosmic-comp triggered on
# multi-output setups.
#
# Compositor-agnostic: it only needs the wlr-layer-shell protocol, which niri,
# cosmic-comp, Hyprland, sway, etc. all provide, so this feature is shared by
# whatever compositor feature wants it (see modules/hm-features/niri.nix and
# modules/hm-features/cosmic.nix, which set myHomeManager.noctalia.enable).
#
# Keybinds are NOT defined here — they are compositor-specific. The shell drives
# everything over `noctalia msg <command>`; wire keys to that from the compositor
# feature using the read-only `cli` handle below. The bar display-mode toggle is
# exposed as a ready-made script (`barModeToggle`).
{ ... }: {
  hmModules.features.noctalia = { config, lib, pkgs, ... }: let
    cfg = config.myHomeManager.noctalia;

    noctaliaPkg = pkgs.noctalia;
    noctaliaExe = lib.getExe noctaliaPkg;

    # Toggle the bar between always-visible (default, good for working) and
    # auto-hide (hidden, reveals on hover at the edge — good for gaming). v5's
    # `bar-auto-hide-set` takes an explicit on/off (no toggle verb), and the
    # config.toml is a read-only nix store symlink so the shell can't persist a
    # runtime flip — so we track the current state in a runtime-dir file and flip
    # it ourselves, mirroring the old v4 helper.
    barModeToggle = pkgs.writeShellScript "noctalia-bar-mode-toggle" ''
      state="''${XDG_RUNTIME_DIR:-/tmp}/noctalia-bar-mode"
      if [ "$(${pkgs.coreutils}/bin/cat "$state" 2>/dev/null)" = "on" ]; then
        next=off
      else
        next=on
      fi
      ${pkgs.coreutils}/bin/echo "$next" > "$state"
      exec ${noctaliaExe} msg bar-auto-hide-set "$next"
    '';
  in {
    options.myHomeManager.noctalia = {
      enable = lib.mkEnableOption "myHomeManager.noctalia";

      # Whether noctalia acts as the org.freedesktop.Notifications daemon. Set
      # false to hand notifications to another shell (e.g. COSMIC's own daemon)
      # and avoid both fighting over the D-Bus name. NOTE: config.toml is a
      # single file shared by every wayland session, so this is global — turning
      # it off also disables noctalia notifications under niri.
      notifications.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether noctalia owns notifications (the freedesktop notification daemon).";
      };

      # Read-only handles so compositor features can wire keybinds without
      # re-deriving these. `cli` is the noctalia binary; drive the shell with
      # `${cli} msg <command>` (v5 talks to the single live instance over its
      # own unix socket — no pid/path juggling like the quickshell v4 needed).
      cli = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        description = "Path to the noctalia binary; use `<cli> msg <command>` to drive the shell.";
      };
      barModeToggle = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        description = "Script toggling the bar between always-visible and auto-hide.";
      };
    };

    config = lib.mkIf cfg.enable {
      myHomeManager.noctalia.cli = noctaliaExe;
      myHomeManager.noctalia.barModeToggle = barModeToggle;

      programs.noctalia = {
        enable = true;
        package = noctaliaPkg;

        # Run noctalia as the homeModule's own user service. It is anchored to the
        # wayland systemd target (graphical-session.target), so it comes up in ANY
        # wayland session (niri or COSMIC), and it attaches X-Restart-Triggers on
        # config.toml + the palettes, so `nh os switch` restarts the shell on any
        # config change — no manual restart.
        systemd.enable = true;

        # Theming (palette, theme.mode/source/custom_palette, fonts, per-surface
        # opacity, wallpaper path) is driven by stylix's native noctalia target
        # (stylix/modules/noctalia/hm.nix), so it is intentionally NOT set here.
        #
        # v5 config.toml. We manage only the non-theme keys we care about; the
        # rest fall back to noctalia's / stylix's defaults. validateConfig
        # (default on) runs `noctalia config validate` at build time, so schema
        # mistakes fail the build rather than silently breaking the shell.
        settings = {
          bar.main = {
            position = "left";
            # always-visible by default; Super+Shift+B flips auto_hide via
            # barModeToggle for gaming.
            auto_hide = false;
            reserve_space = true;
            # Span the full screen height. margin_ends is the inset at each end of
            # the bar along its main axis (top/bottom for a vertical bar); the v5
            # default (180) leaves the floating-bar gap. margin_edge stays at its
            # default (distance from the left screen edge).
            margin_ends = 0;
            # On a vertical (left) bar, start = top and end = bottom. Replicates
            # the v4 layout: launcher/clock/sysmon/active-window/media at the top,
            # workspaces centered, status cluster at the bottom.
            start = [ "launcher" "clock" "sysmon" "active_window" "media" ];
            center = [ "workspaces" ];
            end = [ "tray" ]
              ++ lib.optional cfg.notifications.enable "notifications"
              ++ [ "battery" "volume" "brightness" "bluetooth" "control-center" ];
          };

          # No bottom dock — the left bar already covers launching/window nav.
          dock.enabled = false;

          # enable_daemon = false stops noctalia from claiming the freedesktop
          # notification name, so another daemon (e.g. COSMIC's) can own
          # notifications without a D-Bus name fight. (background_opacity is set
          # by stylix's opacity.popups, not here.)
          notification = {
            enable_daemon = cfg.notifications.enable;
            # Anchor popups bottom-left instead of the default top_right. Accepts
            # kPanelPositions: auto/center/top_{left,center,right}/
            # center_{left,right}/bottom_{left,center,right}.
            position = "bottom_left";
          };

          # swaybg (niri) / cosmic paint the stylix wallpaper; don't let noctalia
          # show its bundled default. (stylix sets wallpaper.default.path, which
          # is harmless while enabled = false.)
          wallpaper.enabled = false;
        };
      };
    };
  };
}
