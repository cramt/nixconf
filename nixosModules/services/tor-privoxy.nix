{pkgs, ...}: let
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .tor-privoxy
    .src;
in {
  config = {
    virtualisation.oci-containers.containers.tor-privoxy = {
      hostname = "tor-privoxy";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
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
