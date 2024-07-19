{ config, lib, ... }:
let
  docker_versions = import ../../docker_versions.nix;
in
{
  config = {
    virtualisation.oci-containers.containers.pihole = {
      hostname = "pihole";
      image = "pihole/pihole:${docker_versions.pihole}";
      ports = [
        "53:53"
      ];
      extraOptions = [
        "--network=caddy"
        "--expose=80"
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
