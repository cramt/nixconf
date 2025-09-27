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
    virtualisation.oci-containers.containers.minecraft-homestead = {
      hostname = "minecraft-forge";
      image = "ghcr.io/cramt/minecraft-homestead-docker:main";
      ports = ["25565:25565"];
      volumes = ["${cfg.dataDir}:/data"];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
      };
      autoStart = false;
    };
  };
}
