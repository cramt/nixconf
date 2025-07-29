{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.jellyfin;
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
      .jellyfin
      .src;
in {
  options.myNixOS.services.jellyfin = {
    mediaVolumes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = ''
        destination for the jellyfin media files
      '';
    };
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the jellyfin mutable config
      '';
    };
    gpuDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        gpu devices to pass to jellyfin
      '';
    };
  };
  config = {
    myNixOS.services.caddy.serviceMap = {
      jellyfin = 8096;
    };
    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers.jellyfin = {
      hostname = "jellyfin";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
      volumes =
        (
          lib.attrsets.mapAttrsToList
          (
            name: value: "${value}:/data/${name}"
          )
          cfg.mediaVolumes
        )
        ++ ["${cfg.configVolume}:/config"];
      extraOptions = builtins.map (d: "--device=${d}:${d}") cfg.gpuDevices;
      ports = [
        "8096:8096"
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
