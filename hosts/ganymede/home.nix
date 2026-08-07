{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.lib) mapAttrs mapAttrs' nameValuePair;

  # One Big Picture tile per browser-based service.
  #
  # Each gets its OWN Firefox profile, which is load-bearing rather than tidy:
  # the kiosks run with MOZ_NO_REMOTE so Steam sees a process that lives as long
  # as the app, and Firefox refuses to open one profile twice. Sharing `default`
  # meant any stray Firefox — including one Plasma restored from a previous
  # session — held the lock and every tile failed to start. Per-site profiles
  # also keep each service independently logged in.
  #
  # ids must be unique across profiles; `default` is 0.
  couchSites = {
    youtube = {
      title = "YouTube";
      url = "https://www.youtube.com";
      id = 1;
    };
    nebula = {
      title = "Nebula";
      url = "https://nebula.tv";
      id = 2;
    };
    jellyfin = {
      title = "Jellyfin";
      url = "https://jellyfin.cramt.dk";
      id = 3;
    };
  };

  couchAddons = with pkgs.nur.repos.rycee.firefox-addons; [
    ublock-origin
    sponsorblock
  ];

  # Kiosk niceties: --kiosk has no chrome to dismiss a prompt with, so anything
  # modal is a dead end from the couch.
  couchPrefs = {
    "browser.aboutConfig.showWarning" = false;
    "browser.tabs.warnOnClose" = false;
    "browser.fullscreen.autohide" = true;
    "full-screen-api.warning.timeout" = 0;
    "browser.shell.checkDefaultBrowser" = false;
    # Never resurrect the last session — a kiosk should always open on its
    # own front page, not on whatever was left over.
    "browser.sessionstore.resume_from_crash" = false;
    # Extensions dropped into a profile directory count as "sideloaded" and
    # Firefox disables them on sight unless told otherwise. Without this the
    # addons are installed but inert, which looks identical to missing.
    "extensions.autoDisableScopes" = 0;
  };

  couchApps =
    mapAttrs (
      profile: site:
        import ../../scripts/couch_browser.nix {
          inherit pkgs profile;
          inherit (site) url;
          name = "couch-${profile}";
          firefox = config.programs.firefox.finalPackage;
        }
    )
    couchSites;
in {
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    bundles.general.enable = true;
    kiosk-kdeconnect = {
      enable = true;
      commands = {
        # `suspend` is a no-op while configuration.nix has sleep fully
        # disabled; kept so the phone still has a shutdown-adjacent control.
        suspend = {name = "Suspend"; command = "systemctl suspend";};
        lock = {name = "Lock Screen"; command = "loginctl lock-session";};
      };
    };

    # One layout for every tile, which is the whole point: YouTube, Jellyfin
    # and Nebula independently settled on YouTube's key convention, so the
    # same button reaches the same feature on all three without a per-site
    # mapping to drift out of sync. Jellyfin's shortcuts were written to
    # "follow youtube as closely as possible" and Nebula's match too.
    #
    # Volume is the one thing they don't agree on — YouTube and Jellyfin put it
    # on the arrows, Nebula doesn't bind it at all — so the triggers drive the
    # system volume instead. On a TV that's the one you actually want anyway.
    steam-input = {
      enable = true;
      layouts."Couch Media" = {
        description = "Browser tiles: YouTube, Jellyfin, Nebula.";
        bindings = {
          button_a = "key_press RETURN"; # activate whatever's focused
          button_b = "key_press ESCAPE"; # back, and leaves fullscreen
          button_x = "key_press K"; # play/pause
          button_y = "key_press F"; # fullscreen

          # Arrows navigate lists and seek ±5s once a player has focus; the
          # stick mirrors the d-pad so either works.
          dpad_north = "key_press UP_ARROW";
          dpad_south = "key_press DOWN_ARROW";
          dpad_east = "key_press RIGHT_ARROW";
          dpad_west = "key_press LEFT_ARROW";
          left_stick_north = "key_press UP_ARROW";
          left_stick_south = "key_press DOWN_ARROW";
          left_stick_east = "key_press RIGHT_ARROW";
          left_stick_west = "key_press LEFT_ARROW";

          left_bumper = "key_press J"; # seek back ~10s
          right_bumper = "key_press L"; # seek forward ~10s

          button_escape = "key_press C"; # subtitles
          button_menu = "key_press M"; # mute

          # Token spelling for the media keys is the one thing here not
          # confirmed against a real controller — if the triggers do nothing,
          # this is the line to look at before anything else.
          left_trigger = "key_press VOLUME_DOWN";
          right_trigger = "key_press VOLUME_UP";
        };
      };
    };

    # The couch tiles, so the Big Picture library is in the repo rather than in
    # a binary blob in the Steam profile. Games come from Steam itself; these
    # are the things that aren't games.
    steam-shortcuts = {
      enable = true;
      shortcuts =
        mapAttrs' (
          profile: site:
            nameValuePair site.title {
              exe = "${couchApps.${profile}}/bin/couch-${profile}";
            }
        )
        couchSites;
    };
  };

  # stylix themes firefox per-profile and refuses to guess the names.
  stylix.targets.firefox.profileNames = ["default"] ++ builtins.attrNames couchSites;

  programs.firefox = {
    enable = true;

    # Home Manager defaults this to the XDG path, .config/mozilla/firefox.
    # Firefox only uses that when ~/.mozilla doesn't already exist, and on
    # ganymede it does (predates this config), so Firefox reads the legacy tree
    # while HM wrote profiles into the XDG one — the declared profiles simply
    # weren't there, which is why the kiosks had no uBlock or SponsorBlock.
    #
    # Pointing HM at the legacy path is the non-destructive fix. The tidier one
    # is to delete ~/.mozilla entirely and let both agree on XDG, since this
    # machine's browser state is disposable; do that and this line comes out.
    configPath = ".mozilla/firefox";

    profiles =
      {
        default = {
          id = 0;
          extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
            plasma-integration
            ublock-origin
            sponsorblock
          ];
          settings = couchPrefs;
        };
      }
      // mapAttrs (_: site: {
        inherit (site) id;
        extensions.packages = couchAddons;
        settings = couchPrefs // {"browser.startup.homepage" = site.url;};
      })
      couchSites;
  };

  # Plasma is the couch shell again (console.mode = "bigpicture"), but only as
  # the thing Big Picture sits on top of — nothing else should be running.
  xdg.configFile = {
    # Never restore the previous session. Plasma's default is to bring back
    # whatever was open at logout, which is how a stray Firefox ended up
    # running at boot and holding the profile lock that the kiosk tiles need.
    # A console should come up in the same state every time.
    "ksmserverrc".text = ''
      [General]
      loginMode=emptySession
    '';

    # A console is watched, not used — long stretches pass with no input at
    # all, and Plasma's locker defaults to grabbing the screen after 5 minutes
    # of that. PowerDevil below only covers dimming/blanking/sleep; the locker
    # is a separate daemon with its own timeout, so it kept firing regardless.
    # Locking on request still works (kdeconnect's `loginctl lock-session`),
    # it just never happens on a timer.
    "kscreenlockerrc".text = ''
      [Daemon]
      Autolock=false
      LockOnResume=false
      LockOnStart=false
      Timeout=0
    '';

    # Disable screen dimming, screen off, and sleep via PowerDevil
    "powerdevilrc".text = ''
      [AC][Display]
      DimDisplayIdleTimeoutSec=-1
      TurnOffDisplayIdleTimeoutSec=-1
      UseProfileSpecificDisplayBrightness=false

      [AC][SuspendAndShutdown]
      AutoSuspendAction=0
      PowerButtonAction=0
      LidAction=0

      [Battery][Display]
      DimDisplayIdleTimeoutSec=-1
      TurnOffDisplayIdleTimeoutSec=-1
      UseProfileSpecificDisplayBrightness=false

      [Battery][SuspendAndShutdown]
      AutoSuspendAction=0
      PowerButtonAction=0
      LidAction=0

      [LowBattery][Display]
      DimDisplayIdleTimeoutSec=-1
      TurnOffDisplayIdleTimeoutSec=-1
      UseProfileSpecificDisplayBrightness=false

      [LowBattery][SuspendAndShutdown]
      AutoSuspendAction=0
      PowerButtonAction=0
      LidAction=0
    '';
  };

  home.packages = [
    # moonlight stays as a fallback for streaming from saturn, but ganymede has
    # its own GPU — games run locally now rather than being streamed in.
    pkgs.moonlight-qt
  ]
  ++ builtins.attrValues couchApps;

  home.stateVersion = "26.05";
}
