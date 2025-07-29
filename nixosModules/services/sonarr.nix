{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.sonarr;
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .sonarr
    .src;
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
      sonarr = 8989;
    };
    virtualisation.oci-containers.containers.sonarr = {
      hostname = "sonarr";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
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
