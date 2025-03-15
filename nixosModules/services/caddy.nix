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
  config = {
    networking.firewall.allowedTCPPorts = [80 443];
    services.caddy = {
      enable = true;
      email = "alex.cramt@gmail.com";
      virtualHosts =
        {
          "(cors)" = {
            extraConfig = ''

              @cors_preflight method OPTIONS

              header {
                ?Access-Control-Allow-Origin "*"
                ?Access-Control-Expose-Headers "Authorization"
                ?Access-Control-Allow-Credentials "true"
                ?Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE"
                ?Access-Control-Max-Age "3600"
              }

              handle @cors_preflight {
                header {
                  ?Access-Control-Allow-Origin "*"
                  Access-Control-Expose-Headers "Authorization"
                  Access-Control-Allow-Credentials "true"
                  Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE"
                  Access-Control-Max-Age "3600"
                }
               respond "" 204
               }
            '';
          };
        }
        // (lib.attrsets.mapAttrs' (name: value: {
            name = "${cfg.protocol}://${name}.${cfg.domain}";
            value = {
              extraConfig = ''
                file_server ${value} browse
              '';
            };
          })
          cfg.staticFileVolumes)
        // (
          if config.myNixOS.services.jellyfin.enable
          then {
            "${cfg.protocol}://jellyfin.${cfg.domain}" = {
              extraConfig = ''
                import cors
                reverse_proxy http://localhost:8096
              '';
            };
          }
          else {}
        )
        // (
          if config.myNixOS.services.qbittorrent.enable
          then {
            "${cfg.protocol}://qbit.${cfg.domain}" = {
              extraConfig = ''
                import cors
                reverse_proxy http://localhost:8080
              '';
            };
          }
          else {}
        )
        // (
          if config.myNixOS.services.foundryvtt.enable
          then {
            "${cfg.protocol}://foundry-a.${cfg.domain}" = {
              extraConfig = ''
                import cors
                reverse_proxy http://localhost:30000
              '';
            };
          }
          else {}
        )
        // (
          if config.myNixOS.services.prowlarr.enable
          then {
            "${cfg.protocol}://prowlarr.${cfg.domain}" = {
              extraConfig = ''
                import cors
                reverse_proxy http://localhost:9696
              '';
            };
          }
          else {}
        )
        // (
          if config.myNixOS.services.radarr.enable
          then {
            "${cfg.protocol}://radarr.${cfg.domain}" = {
              extraConfig = ''
                import cors
                reverse_proxy http://localhost:7878
              '';
            };
          }
          else {}
        )
        // (
          if config.myNixOS.services.sonarr.enable
          then {
            "${cfg.protocol}://sonarr.${cfg.domain}" = {
              extraConfig = ''
                import cors
                reverse_proxy http://localhost:8989
              '';
            };
          }
          else {}
        )
        // (
          if config.myNixOS.services.bazarr.enable
          then {
            "${cfg.protocol}://bazarr.${cfg.domain}" = {
              extraConfig = ''
                import cors
                reverse_proxy http://localhost:6767

              '';
            };
          }
          else {}
        )
        // (
          if config.myNixOS.services.ollama.enable
          then {
            "${cfg.protocol}://ollama.${cfg.domain}" = {
              extraConfig = ''
                import cors
                basic_auth {
                	main $2a$14$rpbR7vq7QsdKBeP.PqjezOi/fWZbBtcHGkIoocOsi0zBlZOgld6cG
                }
                reverse_proxy http://localhost:11434
              '';
            };
          }
          else {}
        )
        // (
          if config.myNixOS.services.servatrice.enable
          then {
            "${cfg.protocol}://cockatrice.${cfg.domain}" = {
              extraConfig = ''
                import cors
                reverse_proxy localhost:4748
              '';
            };
          }
          else {}
        );
    };
  };
}
