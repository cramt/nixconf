{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.prowlarr;
  docker_source = pkgs.npins."linuxserver/prowlarr";
  port = config.port-selector.ports.prowlarr;
in {
  options.myNixOS.services.prowlarr = {
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the config
      '';
    };
  };
  config = {
    myNixOS.services.caddy.serviceMap = {
      prowlarr = {
        port = port;
      };
    };
    port-selector.set-ports."9696" = "prowlarr";
    virtualisation.oci-containers.containers.prowlarr = {
      hostname = "prowlarr";
      imageFile = docker_source;
      image = "${docker_source.image_name}:${docker_source.image_tag}";
      networks = ["piracy"];
      volumes = [
        "${cfg.configVolume}:/config"
      ];
      ports = [
        "${builtins.toString port}:9696"
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
