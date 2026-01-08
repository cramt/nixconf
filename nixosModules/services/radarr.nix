{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.radarr;
  docker_source = pkgs.npinsSources."linuxserver/radarr";
  port = config.port-selector.ports.radarr;
in {
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
    myNixOS.services.caddy.serviceMap = {
      radarr = {
        port = port;
      };
    };
    port-selector.set-ports."7878" = "radarr";
    virtualisation.oci-containers.containers.radarr = {
      hostname = "radarr";
      imageFile = docker_source;
      image = "${docker_source.image_name}:${docker_source.image_tag}";
      networks = ["piracy"];
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.movieVolume}:/movies"
        "${cfg.downloadVolume}:/downloads"
      ];
      ports = ["${builtins.toString port}:7878"];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
      };
      autoStart = true;
    };
  };
}
