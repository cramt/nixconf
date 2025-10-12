{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.sonarr;
  docker_source = pkgs.npins."linuxserver/sonarr";
in {
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
    myNixOS.services.caddy.serviceMap = {
      sonarr = {
        port = 8989;
      };
    };
    virtualisation.oci-containers.containers.sonarr = {
      hostname = "sonarr";
      imageFile = docker_source;
      image = "${docker_source.image_name}:${docker_source.image_tag}";
      networks = ["piracy"];
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.tvVolume}:/tv"
        "${cfg.downloadVolume}:/downloads"
      ];
      ports = [
        "8989:8989"
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
