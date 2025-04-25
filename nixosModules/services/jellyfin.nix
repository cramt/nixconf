{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.jellyfin;
  /*
    docker_source =
      ((import ../../_sources/generated.nix) {
        inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
      })
      .jellyfin
      .src;
  downgrade jellyfin until it work again
  */
  docker_source = pkgs.dockerTools.pullImage {
    imageName = "jellyfin/jellyfin";
    imageDigest = "sha256:b8ce983c7cac30f168a8064a5a1f99fa60b8d131ce0480e8e1b4471039ff1546";
    sha256 = "sha256-vb/rKF0UQNSfA8bG7AWXL7d0OUykduMIzz5mNfJMzaI=";
    finalImageTag = "2025041517";
  };
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
