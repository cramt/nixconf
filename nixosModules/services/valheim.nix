{
  config,
  lib,
  ...
}: let
  cfg = config.myNixOS.services.valheim;
in {
  options.myNixOS.services.valheim = {
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        config volume mount
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
    virtualisation.oci-containers.backend = "docker";
    networking.firewall = {
      allowedUDPPorts = [2456 2457];
      allowedTCPPorts = [2456 2457];
    };
    virtualisation.oci-containers.containers.valheim = {
      hostname = "valheim";
      image = "lloesche/valheim-server:latest";
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.binaryVolume}:/opt/valheim"
      ];
      extraOptions = [
        "-p=2456-2457:2456-2457/udp"
        "--cap-add=sys_nice"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
        SERVER_NAME = cfg.serverName;
        WORLD_NAME = cfg.worldName;
      };
      environmentFiles = [
        config.sops.secrets."valheim/secrets".path
      ];
      autoStart = true;
    };
  };
}
