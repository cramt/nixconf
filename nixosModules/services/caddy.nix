{ config, lib, pkgs, ... }:
let

  cfg = config.myNixOS.services.caddy;
  staticFiles = lib.attrsets.mapAttrsToList
    (name: value: {
      innerFolder = "/${builtins.hashString "md5" name}";
      folder = value;
      subdomain = name;
    })
    cfg.staticFileVolumes;
  docker_versions = import ../../docker_versions.nix;
in
{
  options.myNixOS.services.caddy = {
    cacheVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the caddy to cache tls and stuff
      '';
    };
    staticFileVolumes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = ''
        destinations for the caddy to mount static files
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
      prowlarrCaddy =
        if config.myNixOS.services.prowlarr.enable then ''
          ${cfg.protocol}://prowlarr.${cfg.domain} {
            reverse_proxy http://prowlarr:9696
          }
        '' else "";
      radarrCaddy =
        if config.myNixOS.services.radarr.enable then ''
          ${cfg.protocol}://radarr.${cfg.domain} {
            reverse_proxy http://radarr:7878
          }
        '' else "";
      sonarrCaddy =
        if config.myNixOS.services.sonarr.enable then ''
          ${cfg.protocol}://sonarr.${cfg.domain} {
            reverse_proxy http://sonarr:8989
          }
        '' else "";
      bazarrCaddy =
        if config.myNixOS.services.sonarr.enable then ''
          ${cfg.protocol}://bazarr.${cfg.domain} {
            reverse_proxy http://bazarr:6767
          }
        '' else "";
      piholeCaddy =
        if config.myNixOS.services.pihole.enable then ''
          ${cfg.protocol}://pihole.${cfg.domain} {
            reverse_proxy http://pihole:80
          }
        '' else "";
      staticFileCaddy = lib.strings.concatStringsSep "\n" (
        builtins.map
          (x: ''
            ${cfg.protocol}://${x.subdomain}.${cfg.domain} {
              file_server ${x.innerFolder} browse
            }
          '')
          staticFiles
      );
      caddyFile = pkgs.writeText "Caddyfile" ''
        ${jellyfinCaddy}
        ${qbittorrentCaddy}
        ${foundryvttCaddy}
        ${prowlarrCaddy}
        ${radarrCaddy}
        ${sonarrCaddy}
        ${bazarrCaddy}
        ${piholeCaddy}
        ${staticFileCaddy}
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
        image = "caddy:${docker_versions.caddy}";
        volumes = [
          "${cfg.cacheVolume}/config:/config"
          "${cfg.cacheVolume}/data:/data"
          "${caddyFile}:/etc/caddy/Caddyfile"
        ] ++ builtins.map (x: "${x.innerFolder}:${x.folder} ") staticFiles;
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


