{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.myNixOS.steam;
in {
  options.myNixOS.steam = {
    swayGamingPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        destination for adguards work volume
      '';
    };
  };
  config = {
    programs.gamescope = {
      enable = true;
      package = pkgs.gamescope_git;
    };
    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    };
    environment.systemPackages = with pkgs; [
      mangohud
      steamcmd
    ];
    environment.sessionVariables = {
      STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
    };
    programs.gamemode = {
      enable = true;
      settings = {
        custom =
          if cfg.swayGamingPackage != null
          then {
            start = "${cfg.swayGamingPackage}/bin/sway_gaming true";
            end = "${cfg.swayGamingPackage}/bin/sway_gaming false";
          }
          else {};
      };
    };
    systemd.user.services.steam_background = {
      enable = true;
      description = "Open Steam in the background at boot";
      wantedBy = ["graphical-session.target"];
      serviceConfig = {
        ExecStart = "${pkgs.steam}/bin/steam -nochatui -nofriendsui -silent %U";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
