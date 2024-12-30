{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.qbittorrent;
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .qbittorrent
    .src;
in {
  options.myNixOS.services.qbittorrent = {
    downloadVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the downloads
      '';
    };
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the config
      '';
    };
  };
  config = {
    virtualisation.oci-containers.containers.qbittorrent = {
      hostname = "qbittorrent";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.downloadVolume}:/downloads"
      ];
      extraOptions = [
        "--network=caddy"
        "--expose=8080"
      ];
      ports = [
        "6881:6881"
        "6881:6881/udp"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
        WEBUI_PORT = "8080";
      };
      autoStart = true;
    };
  };
}
