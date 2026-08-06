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

  jellyfin = pkgs.jellyfin-media-player;
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

    # The couch tiles, so the Big Picture library is in the repo rather than in
    # a binary blob in the Steam profile. Games come from Steam itself; these
    # are the things that aren't games.
    steam-shortcuts = {
      enable = true;
      shortcuts =
        {
          "Jellyfin" = {
            exe = "${jellyfin}/bin/jellyfin-desktop";
            # Jellyfin Desktop's UI is a QtWebEngine view, and Steam's overlay
            # segfaults its renderer process on launch
            # (gameoverlayrenderer.so, SIGSEGV in QtWebEngineProcess). Nothing
            # here needs the overlay; the browsers keep it for the on-screen
            # keyboard.
            overlay = false;
          };
        }
        // mapAttrs' (
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

  # Jellyfin Desktop ships desktop defaults: windowed, and its pointer-oriented
  # "desktop" web layout rather than the 10-foot one. Both are wrong on a TV.
  #
  # Its settings live under a generated per-profile directory, so there's no
  # static path to point home.file at — hence a merge over whatever profiles
  # exist, which also leaves JMP free to own every other key. Boot ordering is
  # the same as the Steam shortcuts: activation runs before the session, so
  # this lands before Jellyfin is ever launched.
  home.activation.jellyfinCouchSettings =
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      for f in "$HOME"/.local/share/jellyfin-desktop/profiles/*/jellyfin-desktop.conf; do
        [ -e "$f" ] || continue
        ${pkgs.jq}/bin/jq '.sections.main.fullscreen    = true
                         | .sections.main.forceAlwaysFS = true
                         | .sections.main.layout        = "tv"
                         | .sections.main.webMode       = "tv"' "$f" > "$f.tmp" \
          && mv "$f.tmp" "$f"
      done
    '';

  home.packages = [
    # moonlight stays as a fallback for streaming from saturn, but ganymede has
    # its own GPU — games run locally now rather than being streamed in.
    pkgs.moonlight-qt

    # Jellyfin is the one service that gets a native client instead of a tab.
    # Browsers can't direct-play most of what's on luna, so a Jellyfin tab
    # would push luna's 1660 into transcoding every stream; the mpv-backed
    # client direct-plays it. Upstream renamed this Jellyfin Desktop in 2.0 —
    # the binary is `jellyfin-desktop`, the nixpkgs attr is still the old name.
    # If you'd rather it were a tab too, add it to couchSites above.
    jellyfin
  ]
  ++ builtins.attrValues couchApps;

  home.stateVersion = "26.05";
}
