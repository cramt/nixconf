{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.minecraft-forge;
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .minecraft-server
    .src;
in {
  options.myNixOS.services.minecraft-forge = {
    url = lib.mkOption {
      type = lib.types.str;
      description = ''
        mod page like fx https://www.curseforge.com/minecraft/modpacks/all-the-mods-8
      '';
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        dir to store data
      '';
    };
  };
  config = {
    virtualisation.oci-containers.containers.minecraft-forge = {
      hostname = "minecraft-forge";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
      ports = ["25565:25565"];
      volumes = ["${cfg.dataDir}:/data"];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
        TYPE = "AUTO_CURSEFORGE";
        CF_PAGE_URL = cfg.url;
        EULA = "TRUE";
      };
      environmentFiles = [
        config.sops.secrets."minecraft_server".path
      ];
    };
  };
}
