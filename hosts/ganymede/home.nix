{
  input,
  inputs,
  outputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [outputs.homeManagerModules.default];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    bundles.general.enable = true;
    kiosk-kdeconnect = {
      enable = true;
      commands = {
        suspend = {name = "Suspend"; command = "systemctl suspend";};
        lock = {name = "Lock Screen"; command = "loginctl lock-session";};
        open-url = {name = "Open URL from Clipboard"; command = "firefox --kiosk $(wl-paste)";};
      };
    };
  };

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

  # Plasma kiosk configuration
  xdg.configFile = {
    # Force Firefox fullscreen via KWin window rule
    "kwinrulesrc".text = ''
      [1]
      Description=Firefox Fullscreen
      fullscreen=true
      fullscreenrule=3
      wmclass=firefox
      wmclassmatch=1
    '';

    # Hide the panel/taskbar
    "plasmashellrc".text = ''
      [PlasmaViews][Panel 2]
      panelVisibility=2
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

  # Autostart Firefox in kiosk mode
  xdg.configFile."autostart/firefox-kiosk.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Firefox Kiosk
    Exec=firefox --kiosk
    X-KDE-autostart-phase=2
  '';

  home.packages = [pkgs.moonlight-qt];

  home.stateVersion = "25.11";
}
