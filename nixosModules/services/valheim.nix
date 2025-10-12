{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.valheim;
  docker_source = pkgs.npins."mbround18/valheim";
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
      image = "${docker_source.image_name}:${docker_source.image_tag}";
      ports = [
        "2456:2456/udp"
        "2457:2457/udp"
        "2458:2458/udp"
      ];
      environment = {
        PUID = "111";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
        PORT = "2456";
        NAME = cfg.serverName;
        WORLD = cfg.worldName;
        PUBLIC = "0";
        AUTO_UPDATE = "0";
        PASSWORD = (import ../../secrets.nix).valheim_password;
        TYPE = "BepInEx";
        MODS = ''
          denikson-BepInExPack_Valheim-5.4.2202
          Azumatt-Official_BepInEx_ConfigurationManager-18.4.1
          Advize-PlantEverything-1.19.1
          ValheimModding-Jotunn-2.26.0
          RustyMods-Seasonality-3.5.9
          Valphi-BetterLaddersContinued-0.217.24
          Pineapple-TorchesEternal-0.3.0
          N3xus-FarmGrid-0.2.0
          blacks7ar-FeatherCollector-1.1.8
          Azumatt-AzuClock-1.0.5
          JereKuusela-Server_devcommands-1.97.0
        '';
      };
      extraOptions = [
        "--shm-size=2gb"
        "--cpu-shares=10"
      ];
      capabilities = {
        SYS_ADMIN = true;
      };
      volumes = [
        "${cfg.worldVolume}:/home/steam/.config/unity3d/IronGate/Valheim"
        "${cfg.binaryVolume}:/home/steam/valheim"
      ];
      autoStart = false;
    };
  };
}
