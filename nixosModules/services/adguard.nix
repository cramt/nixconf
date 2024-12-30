{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.adguard;
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .adguard
    .src;
in {
  options.myNixOS.services.adguard = {
    workVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for adguards work volume
      '';
    };
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for adguards config volume
      '';
    };
  };
  config = {
    networking.firewall = {
      allowedUDPPorts = [53];
      allowedTCPPorts = [53];
    };
    virtualisation.oci-containers.containers.adguard = {
      hostname = "adguard";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
      volumes = [
        "${cfg.configVolume}:/opt/adguardhome/conf"
        "${cfg.workVolume}:/opt/adguardhome/work"
      ];
      ports = [
        "53:53/udp"
        "53:53/tcp"
      ];
      extraOptions = [
        "--network=caddy"
        "--expose=3000"
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
