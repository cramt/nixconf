{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.caddy;
  staticFiles =
    lib.attrsets.mapAttrsToList
    (name: value: {
      innerFolder = "/${builtins.hashString "md5" name}";
      folder = value;
      subdomain = name;
    })
    cfg.staticFileVolumes;
  docker_source =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .caddy
    .src;
in {
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
      type = lib.types.enum ["http" "https"];
      default = "https";
      description = ''
        protocol to use
      '';
    };
  };
  config = let
    jellyfinCaddy =
      if config.myNixOS.services.jellyfin.enable
      then ''
        ${cfg.protocol}://jellyfin.${cfg.domain} {
          reverse_proxy http://jellyfin:8096
        }
      ''
      else "";
    qbittorrentCaddy =
      if config.myNixOS.services.qbittorrent.enable
      then ''
        ${cfg.protocol}://qbit.${cfg.domain} {
          reverse_proxy http://qbittorrent:8080
        }
      ''
      else "";
    foundryvttCaddy =
      if config.myNixOS.services.foundryvtt.enable
      then ''
        ${cfg.protocol}://foundry-a.${cfg.domain} {
          reverse_proxy http://foundryvtt:30000
        }
      ''
      else "";
    prowlarrCaddy =
      if config.myNixOS.services.prowlarr.enable
      then ''
        ${cfg.protocol}://prowlarr.${cfg.domain} {
          reverse_proxy http://prowlarr:9696
        }
      ''
      else "";
    radarrCaddy =
      if config.myNixOS.services.radarr.enable
      then ''
        ${cfg.protocol}://radarr.${cfg.domain} {
          reverse_proxy http://radarr:7878
        }
      ''
      else "";
    sonarrCaddy =
      if config.myNixOS.services.sonarr.enable
      then ''
        ${cfg.protocol}://sonarr.${cfg.domain} {
          reverse_proxy http://sonarr:8989
        }
      ''
      else "";
    bazarrCaddy =
      if config.myNixOS.services.bazarr.enable
      then ''
        ${cfg.protocol}://bazarr.${cfg.domain} {
          reverse_proxy http://bazarr:6767
        }
      ''
      else "";
    servatriceCaddy =
      if config.myNixOS.services.servatrice.enable
      then ''
        ${cfg.protocol}://cockatrice.${cfg.domain} {
          reverse_proxy servatrice:4748
        }
      ''
      else "";
    adguardCaddy =
      if config.myNixOS.services.adguard.enable
      then ''
        ${cfg.protocol}://adguard_setup.${cfg.domain} {
          reverse_proxy http://adguard:3000
        }
        ${cfg.protocol}://adguard.${cfg.domain} {
          reverse_proxy http://adguard:80
        }
      ''
      else "";
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
      ${servatriceCaddy}
      ${adguardCaddy}
      ${staticFileCaddy}
    '';
  in {
    virtualisation.oci-containers.backend = "docker";
    systemd.services.docker-create-caddy-network = {
      serviceConfig.Type = "oneshot";
      wantedBy = ["docker-caddy.service"];
      script = let
        sudo_docker = "${pkgs.sudo}/bin/sudo ${pkgs.docker}/bin/docker";
      in ''
        ${sudo_docker} network inspect caddy >/dev/null 2>&1 || ${sudo_docker} network create --driver bridge caddy
      '';
    };
    virtualisation.oci-containers.containers.caddy = {
      hostname = "caddy";
      imageFile = docker_source;
      image = "${docker_source.imageName}:${docker_source.imageTag}";
      volumes =
        [
          "${cfg.cacheVolume}/config:/config"
          "${cfg.cacheVolume}/data:/data"
          "${caddyFile}:/etc/caddy/Caddyfile"
        ]
        ++ builtins.map (x: "${x.innerFolder}:${x.folder} ") staticFiles;
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
