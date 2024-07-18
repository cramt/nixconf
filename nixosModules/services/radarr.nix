{ config, lib, ... }:
let
  cfg = config.myNixOS.services.radarr;
  docker_versions = import ../../docker_versions.nix;
in
{
  options.myNixOS.services.radarr = {
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
    movieVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the downloads
      '';
    };
  };
  config = {
    virtualisation.oci-containers.containers.radarr = {
      hostname = "radarr";
      image = "ghcr.io/hotio/radarr:${docker_versions.radarr}";
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.movieVolume}:/movies"
        "${cfg.downloadVolume}:/downloads"
      ];
      extraOptions = [
        "--network=caddy"
        "--expose=7878"
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
