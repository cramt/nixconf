{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.minecraft-homestead;
in {
  options.myNixOS.services.minecraft-homestead = {
    dataDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        dir to store data
      '';
    };
  };
  config = {
    networking.firewall = {
      allowedUDPPorts = [25565 24454];
      allowedTCPPorts = [25565 24454];
    };
    virtualisation.oci-containers.containers.minecraft-homestead = {
      hostname = "minecraft-forge";
      image = "ghcr.io/cramt/minecraft-homestead-docker:main";
      ports = [
        "25565:25565"
        "24454:24454/udp"
      ];
      volumes = ["${cfg.dataDir}:/data"];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
      };
      autoStart = true;
    };
  };
}
