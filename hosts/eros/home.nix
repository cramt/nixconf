# eros couch shell (v2) — home-manager
#
# eros is a Raspberry Pi 4B wired to the living-room TV, driven by a Steam
# Controller over Bluetooth. v1 used Kodi-on-GBM as the shell, which forced a
# whole-session-switch model (only one app can own the KMS master, and kodi-gbm
# can't nest a KMS child) — that's where all the v1 hackery lived (marker file,
# SIGTERM/SIGKILL-Kodi dance, sqlite addon seeding, greetd churn).
#
# v2 drops Kodi entirely. sway is the persistent shell; every app (Steam Link,
# Moonlight, Firefox) is an ordinary Wayland client. The "console menu" is a
# wofi launcher run in a supervisor loop: show menu -> pick -> run app in the
# foreground -> app exits -> menu returns. No KMS juggling, no kill dance.
#
# Steam Controller: over Bluetooth it presents as a HID mouse+keyboard ("lizard
# mode") — so the menu is driven natively by the right trackpad (mouse + click)
# and the d-pad/arrows + A/Enter. No sc-controller needed (that was the flaky
# bit in v1), which is the whole point of "Steam Controller native" here: the
# trackpad-as-mouse is the controller's signature strength, so a point-and-click
# menu IS the native paradigm for this pad.
{ config, pkgs, lib, ... }:
let
  # Their patched Steam Link (aarch64) — same package v1 shipped.
  steamlink = pkgs.callPackage ../../packages/steamlink { };

  # The addon-configured Firefox (uBlock + SponsorBlock), by store path so the
  # launcher doesn't depend on PATH inside the greetd-launched sway session.
  firefox = config.programs.firefox.finalPackage;

  # ---- Destinations -------------------------------------------------------
  # YouTube's /tv (leanback) UI is built for d-pad navigation — far better on a
  # controller than the desktop site. Jellyfin + Nebula are plain kiosk tabs.
  youtubeUrl  = "https://www.youtube.com/tv";
  jellyfinUrl = "http://jellyfin.lan:8096";   # TODO: point at your Jellyfin server
  nebulaUrl   = "https://nebula.tv";

  # ---- Launcher styling ---------------------------------------------------
  wofiConf = pkgs.writeText "eros-wofi.conf" ''
    show=dmenu
    width=680
    height=620
    location=center
    prompt=eros
    insensitive=true
    allow_markup=true
    hide_scroll=true
    no_actions=true
    lines=7
    columns=1
  '';

  wofiStyle = pkgs.writeText "eros-wofi.css" ''
    * {
      font-family: "sans-serif";
      font-size: 32px;
    }
    window {
      background-color: rgba(8, 10, 20, 0.97);
      border-radius: 22px;
      padding: 28px;
    }
    #input {
      margin: 8px 8px 18px 8px;
      padding: 16px 20px;
      border: none;
      border-radius: 14px;
      background-color: rgba(255, 255, 255, 0.06);
      color: #dfe6f2;
    }
    #inner-box { margin: 6px; }
    #entry {
      padding: 18px 26px;
      margin: 5px 8px;
      border-radius: 16px;
    }
    #entry:selected { background-color: #2a6df4; }
    #text { color: #dfe6f2; }
    #entry:selected #text { color: #ffffff; }
  '';

  # ---- The couch shell ----------------------------------------------------
  # Runs as sway's startup exec. Never returns; a picked app runs in the
  # foreground and quitting it drops straight back to the menu. Every branch is
  # `|| true` + a trailing sleep so a failed launch can't hot-loop the TV.
  #
  # MOZ_NO_REMOTE forces each `firefox --kiosk` to be its own blocking instance
  # (otherwise a second invocation just hands the URL to the running one and
  # returns immediately, flashing the menu).
  couchShell = pkgs.writeShellScript "eros-couch-shell" ''
    export MOZ_ENABLE_WAYLAND=1
    export MOZ_NO_REMOTE=1
    export QT_QPA_PLATFORM=wayland

    menu() {
      ${pkgs.wofi}/bin/wofi --dmenu --cache-file /dev/null \
        --conf ${wofiConf} --style ${wofiStyle} --prompt "eros"
    }

    while true; do
      choice=$(${pkgs.coreutils}/bin/printf '%s\n' \
        "🎮   Steam Link" \
        "🌙   Moonlight" \
        "▶    YouTube" \
        "🎬   Jellyfin" \
        "🌌   Nebula" \
        "⏻    Power Off" \
        "⭮    Restart Shell" | menu) || choice=""

      case "$choice" in
        *"Steam Link")    ( ${steamlink}/bin/steamlink ) || true ;;
        *"Moonlight")     ( ${pkgs.moonlight-qt}/bin/moonlight ) || true ;;
        *"YouTube")       ( ${firefox}/bin/firefox --kiosk "${youtubeUrl}" ) || true ;;
        *"Jellyfin")      ( ${firefox}/bin/firefox --kiosk "${jellyfinUrl}" ) || true ;;
        *"Nebula")        ( ${firefox}/bin/firefox --kiosk "${nebulaUrl}" ) || true ;;
        *"Power Off")     ${pkgs.systemd}/bin/systemctl poweroff || true ;;
        *"Restart Shell") ${pkgs.sway}/bin/swaymsg exit || true ;;
        *) : ;;  # Escape / empty selection -> just redraw the menu
      esac
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
in
{
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";
  home.stateVersion = "26.05";

  home.packages = [
    pkgs.wofi
    pkgs.moonlight-qt
    steamlink
    pkgs.foot          # lightweight debug terminal (Mod4+Return)
    pkgs.wl-clipboard
  ];

  programs.firefox = {
    enable = true;
    profiles.default = {
      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        sponsorblock
      ];
      settings = {
        # Kiosk niceties: no close/fullscreen nags, autohide chrome in FS.
        "browser.aboutConfig.showWarning" = false;
        "browser.tabs.warnOnClose" = false;
        "browser.fullscreen.autohide" = true;
        "full-screen-api.warning.timeout" = 0;
        "browser.shell.checkDefaultBrowser" = false;

        # --- Pi 4 V3D GPU stability -----------------------------------------
        # If Firefox crashes / black-screens on launch (the v1 symptom), flip
        # these on: force software WebRender and disable VA-API. Left off by
        # default because the earlier "normal compositor" test ran smoother
        # WITHOUT them, and we want to confirm the real cause from logs first
        # (the crash may instead be the force-disabled xdg portals — see
        # configuration.nix). Toggle one axis at a time when testing on eros.
        # "gfx.webrender.software" = true;
        # "media.ffmpeg.vaapi.enabled" = false;
        # "widget.dmabuf.force-enabled" = false;
      };
    };
  };

  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;               # Steam Link (SDL) may fall back to XWayland
    wrapperFeatures.gtk = true;
    config = {
      modifier = "Mod4";
      terminal = "${pkgs.foot}/bin/foot";
      bars = [ ];                  # kiosk: no status bar
      gaps = { inner = 0; outer = 0; };

      # Pin 1080p (the kernel video= line already forces it; this keeps sway in
      # agreement) and paint the background the launcher's dark blue so there's
      # never a grey flash between the menu closing and an app painting.
      output."*" = {
        mode = "1920x1080";
        bg = "#0a0c14 solid_color";
      };

      # Single-app kiosk: fullscreen everything, no borders/titlebars. wofi is
      # a layer-shell surface and is unaffected by these window rules.
      window = {
        border = 0;
        titlebar = false;
        commands = [
          { criteria = { app_id = ".*"; }; command = "fullscreen enable, border none"; }
          { criteria = { class = ".*"; };  command = "fullscreen enable, border none"; }
        ];
      };
      floating = { border = 0; titlebar = false; };

      keybindings = {
        "Mod4+q" = "kill";                       # force-quit foreground app -> menu
        "Mod4+Return" = "exec ${pkgs.foot}/bin/foot";
        "Mod4+Shift+q" = "exec ${pkgs.sway}/bin/swaymsg exit";
      };

      input."*" = {
        xkb_layout = "dk";
        xkb_variant = "nodeadkeys";
      };

      startup = [
        { command = "${couchShell}"; always = false; }
      ];
    };
  };
}
