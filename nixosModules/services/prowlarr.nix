{ config, lib, ... }:
let
  cfg = config.myNixOS.services.prowlarr;
  docker_versions = import ../../docker_versions.nix;
in
{
  options.myNixOS.services.prowlarr = {
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the config
      '';
    };
  };
  config = {
    virtualisation.oci-containers.containers.prowlarr = {
      hostname = "prowlarr";
      image = "ghcr.io/hotio/prowlarr:${docker_versions.prowlarr}";
      volumes = [
        "${cfg.configVolume}:/config"
      ];
      extraOptions = [
        "--network=caddy"
        "--expose=9696"
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
