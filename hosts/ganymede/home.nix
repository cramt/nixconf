{
  config,
  pkgs,
  ...
}: let
  # One Big Picture tile per service. finalPackage rather than pkgs.firefox so
  # the kiosk inherits the profile configured below — SponsorBlock in
  # particular is what makes couch YouTube tolerable.
  couch = name: url:
    import ../../scripts/couch_browser.nix {
      inherit pkgs name url;
      firefox = config.programs.firefox.finalPackage;
    };
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
  };

  # stylix themes firefox per-profile and refuses to guess the names.
  stylix.targets.firefox.profileNames = ["default"];

  programs.firefox = {
    enable = true;
    profiles.default = {
      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        plasma-integration
        ublock-origin
        sponsorblock
      ];
      settings = {
        # --kiosk has no chrome to dismiss a prompt with, so anything modal is
        # a dead end from the couch.
        "browser.aboutConfig.showWarning" = false;
        "browser.tabs.warnOnClose" = false;
        "browser.fullscreen.autohide" = true;
        "full-screen-api.warning.timeout" = 0;
        "browser.shell.checkDefaultBrowser" = false;
      };
    };
  };

  # Plasma is no longer the couch shell — it's the "switch to desktop" target
  # behind the gamescope session — so the kiosk-era KWin fullscreen rule and
  # hidden panel are gone. Only the power settings still earn their place: a TV
  # that blanks mid-film is just as annoying from Big Picture.
  xdg.configFile = {
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

    # Jellyfin is the one service that gets a native client instead of a tab.
    # Browsers can't direct-play most of what's on luna, so a Jellyfin tab
    # would push luna's 1660 into transcoding every stream; the mpv-backed
    # client direct-plays it. Upstream renamed this Jellyfin Desktop in 2.0 —
    # the binary is `jellyfin-desktop`, the nixpkgs attr is still the old name.
    # If you'd rather it were a tab too, it's `(couch "couch-jellyfin"
    # "https://jellyfin.cramt.dk")`.
    pkgs.jellyfin-media-player

    (couch "couch-youtube" "https://www.youtube.com")
    (couch "couch-nebula" "https://nebula.tv")
  ];

  home.stateVersion = "26.05";
}
