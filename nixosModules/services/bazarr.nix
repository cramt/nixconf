{ config, lib, ... }:
let
  cfg = config.myNixOS.services.bazarr;
in
{
  options.myNixOS.services.bazarr = {
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the config
      '';
    };
    movieVolume = lib.mkOption {
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
    downloadVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the downloads
      '';
    };
  };
  config = {
    virtualisation.oci-containers.containers.bazarr = {
      hostname = "bazarr";
      image = "ghcr.io/hotio/bazarr";
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.movieVolume}:/movies"
        "${cfg.tvVolume}:/tv"
        "${cfg.downloadVolume}:/downloads"
      ];
      extraOptions = [
        "--network=caddy"
        "--expose=6767"
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
