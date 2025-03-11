{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.valheim;
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .odin
    .src;
in {
  options.myNixOS.services.valheim = {
    worldVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        world volume mount
      '';
    };
    binaryVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        binary volume mount
      '';
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      description = ''
        server name
      '';
    };

    worldName = lib.mkOption {
      type = lib.types.str;
      description = ''
        world name
      '';
    };
  };
  config = {
    networking.firewall = {
      allowedUDPPorts = [2456 2457 2458];
      allowedTCPPorts = [2456 2457 2458];
    };
    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers.valheim = {
      hostname = "valheim";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
      ports = [
        "2456:2456/udp"
        "2457:2457/udp"
        "2458:2458/udp"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
        PORT = "2456";
        NAME = "valheim server";
        WORLD = "Dedicated";
        PUBLIC = "0";
        AUTO_UPDATE = "0";
        PASSWORD = "12345";
      };
      volumes = [
        "${cfg.worldVolume}:/home/steam/.config/unity3d/IronGate/Valheim"
        "${cfg.binaryVolume}:/home/steam/valheim"
      ];
      autoStart = false;
    };
  };
}
