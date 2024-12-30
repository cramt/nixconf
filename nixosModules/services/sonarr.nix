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
    virtualisation.oci-containers.containers.sonarr = {
      hostname = "sonarr";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
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
