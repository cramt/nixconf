{ config, lib, pkgs, ... }:
let

  cfg = config.myNixOS.services.caddy;
in
{
  options.myNixOS.services.caddy = {
    cacheVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the caddy to cache tls and stuff
      '';
    };
    staticFileVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the caddy to mount static files
      '';
    };
    domain = lib.mkOption {
      type = lib.types.str;
      description = ''
        tld to use
      '';
    };
    protocol = lib.mkOption {
      type = lib.types.enum [ "http" "https" ];
      default = "https";
      description = ''
        protocol to use
      '';
    };
  };
  config =
    let
      jellyfinCaddy =
        if config.myNixOS.services.jellyfin.enable then ''
          ${cfg.protocol}://jellyfin.${cfg.domain} {
            reverse_proxy http://jellyfin:8096
          }
        '' else "";
      qbittorrentCaddy =
        if config.myNixOS.services.qbittorrent.enable then ''
          ${cfg.protocol}://qbit.${cfg.domain} {
            reverse_proxy http://qbittorrent:8080
          }
        '' else "";
      foundryvttCaddy =
        if config.myNixOS.services.foundryvtt.enable then ''
          ${cfg.protocol}://foundry-a.${cfg.domain} {
            reverse_proxy http://foundryvtt:30000
          }
        '' else "";
      caddyFile = pkgs.writeText "Caddyfile" ''
        ${jellyfinCaddy}
        ${qbittorrentCaddy}
        ${foundryvttCaddy}
      '';
    in
    {
      virtualisation.oci-containers.backend = "docker";
      systemd.services.docker-create-caddy-network = {
        serviceConfig.Type = "oneshot";
        wantedBy = [ "docker-caddy.service" ];
        script =
          let
            sudo_docker = "${pkgs.sudo}/bin/sudo ${pkgs.docker}/bin/docker";
          in
          ''
            ${sudo_docker} network inspect caddy >/dev/null 2>&1 || ${sudo_docker} network create --driver bridge caddy
          '';
      };
      virtualisation.oci-containers.containers.caddy = {
        hostname = "caddy";
        image = "caddy";
        volumes = [
          "${cfg.cacheVolume}/config:/config"
          "${cfg.cacheVolume}/data:/data"
          "${caddyFile}:/etc/caddy/Caddyfile"
          "${cfg.staticFileVolume}:/files/"
        ];
        ports = [
          "443:443"
          "80:80"
          "2019:2019"
        ];
        extraOptions = [
          "--network=caddy"
        ];
        environment = {
          EMAIL = "alex.cramt@gmail.com";
        };
        autoStart = true;
      };
    };
}

