{...}: {
  flake.nixosModules."services.satisfactory" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.satisfactory;
    docker_source = pkgs.npinsSources."wolveix/satisfactory-server";
  in {
    options.myNixOS.services.satisfactory = {
      enable = lib.mkEnableOption "myNixOS.services.satisfactory";
      dataVolume = lib.mkOption {
        type = lib.types.str;
        description = ''
          volume mount for satisfactory server data (/config)
        '';
      };

      maxPlayers = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = ''
          maximum number of players
        '';
      };

      beta = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          use the experimental/beta branch
        '';
      };
    };
    config = lib.mkIf cfg.enable {
      networking.firewall = {
        allowedUDPPorts = [7777];
        allowedTCPPorts = [7777 8888];
      };
      virtualisation.oci-containers.backend = "docker";
      virtualisation.oci-containers.containers.satisfactory = {
        hostname = "satisfactory";
        imageFile = docker_source;
        image = "${docker_source.image_name}:${docker_source.image_tag}";
        ports = [
          "7777:7777/tcp"
          "7777:7777/udp"
          "8888:8888/tcp"
        ];
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "Europe/Copenhagen";
          MAXPLAYERS = toString cfg.maxPlayers;
          SKIPUPDATE = "false";
          STEAMBETA =
            if cfg.beta
            then "true"
            else "false";
        };
        volumes = [
          "${cfg.dataVolume}:/config"
        ];
        extraOptions = [
          "--memory-reservation=4g"
          "--memory=8g"
        ];
        autoStart = true;
      };
    };
  };
}
