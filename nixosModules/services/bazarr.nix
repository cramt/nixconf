{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.bazarr;
  docker_source = pkgs.npinsSources."linuxserver/bazarr";

  port = config.port-selector.ports.bazarr;
in {
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
    myNixOS.services.caddy.serviceMap.bazarr.port = port;
    port-selector.set-ports."6767" = "bazarr";
    virtualisation.oci-containers.containers.bazarr = {
      hostname = "bazarr";
      imageFile = docker_source;
      image = "${docker_source.image_name}:${docker_source.image_tag}";
      networks = ["piracy"];
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.movieVolume}:/movies"
        "${cfg.tvVolume}:/tv"
        "${cfg.downloadVolume}:/downloads"
      ];
      ports = [
        "${builtins.toString port}:6767"
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
