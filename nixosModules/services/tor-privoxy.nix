{ config, lib, ... }:
let
  docker_versions = import ../../docker_versions.nix;
in
{
  config = {
    virtualisation.oci-containers.containers.tor-privoxy = {
      hostname = "tor-privoxy";
      image = "dockage/tor-privoxy:${docker_versions.tor-privoxy}";
      extraOptions = [
        "--network=caddy"
        "--expose=9050"
        "--expose=9051"
        "--expose=8118"
      ];
      autoStart = true;
    };
  };
}
