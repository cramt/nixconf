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
  port = config.port-selector.ports.qbit;
  udp_port = config.port-selector.ports.qbit_udp;
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
    myNixOS.services.caddy.serviceMap = {
      qbit = {
        port = port;
      };
    };
    port-selector.set-ports = {
      "6881" = "qbit_udp";
      "8080" = "qbit";
    };
    systemd.services.docker-create-piracy-network = {
      serviceConfig.Type = "oneshot";
      script = let
        sudo_docker = "${pkgs.sudo}/bin/sudo ${pkgs.docker}/bin/docker";
      in ''
        ${sudo_docker} network inspect piracy >/dev/null 2>&1 || ${sudo_docker} network create --driver bridge piracy

      '';
    };
    virtualisation.oci-containers.containers.qbittorrent = {
      hostname = "qbittorrent";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
      networks = ["piracy"];
      volumes = [
        "${cfg.configVolume}:/config"
        "${cfg.downloadVolume}:/downloads"
      ];
      ports = [
        "${builtins.toString udp_port}:6881"
        "${builtins.toString udp_port}:6881/udp"
        "${builtins.toString port}:8080"
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
