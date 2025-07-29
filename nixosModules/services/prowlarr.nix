{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.prowlarr;
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .prowlarr
    .src;
in {
  options.myNixOS.services.prowlarr = {
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the config
      '';
    };
  };
  config = {
    myNixOS.services.caddy.serviceMap = {
      prowlarr = 9696;
    };
    virtualisation.oci-containers.containers.prowlarr = {
      hostname = "prowlarr";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
      networks = ["piracy"];
      volumes = [
        "${cfg.configVolume}:/config"
      ];
      ports = [
        "9696:9696"
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
