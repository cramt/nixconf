# Steam gaming with Gamescope and GameMode
{ ... }: {
  flake.nixosModules."features.steam" = { config, lib, pkgs, ... }: {
    options.myNixOS.steam.enable = lib.mkEnableOption "myNixOS.steam";
    config = lib.mkIf config.myNixOS.steam.enable {
      programs.gamescope.enable = true;
      programs.steam = {
        enable = true;
        gamescopeSession.enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
      };
      environment.systemPackages = with pkgs; [
        mangohud
        steamcmd
      ];
      environment.sessionVariables = {
        STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
      };
      programs.gamemode.enable = true;
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
  };
}
