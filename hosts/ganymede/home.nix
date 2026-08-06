{
  config,
  pkgs,
  ...
}: {
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

  # moonlight stays as a fallback for streaming from saturn, but ganymede has
  # its own GPU — games run locally now rather than being streamed in.
  home.packages = [pkgs.moonlight-qt];

  home.stateVersion = "26.05";
}
