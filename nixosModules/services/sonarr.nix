{ config, lib, ... }:
let
  cfg = config.myNixOS.services.sonarr;
in
{
  options.myNixOS.services.sonarr = {
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the config
      '';
    };
    downloadVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the downloads
      '';
    };
    tvVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the downloads
      '';
    };
  };
  config = {
    virtualisation.oci-containers.containers.sonarr = {
      hostname = "sonarr";
      image = "ghcr.io/hotio/sonarr";
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.tvVolume}:/tv"
        "${cfg.downloadVolume}:/downloads"
      ];
      extraOptions = [
        "--network=caddy"
        "--expose=8989"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
      };
      autoStart = true;
    };
  };
}
