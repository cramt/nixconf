{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.bazarr;
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .bazarr
    .src;
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
    myNixOS.services.caddy.serviceMap = {
      bazarr = 6767;
    };
    virtualisation.oci-containers.containers.bazarr = {
      hostname = "bazarr";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
      networks = ["piracy"];
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.movieVolume}:/movies"
        "${cfg.tvVolume}:/tv"
        "${cfg.downloadVolume}:/downloads"
      ];
      ports = [
        "6767:6767"
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
