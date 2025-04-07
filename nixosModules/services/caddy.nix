{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.caddy;
  services =
    (lib.attrsets.mapAttrs' (name: value: {
        name = "${name}.${cfg.domain}";
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
        "jellyfin.${cfg.domain}" = {
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
        "qbit.${cfg.domain}" = {
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
        "foundry-a.${cfg.domain}" = {
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
        "prowlarr.${cfg.domain}" = {
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
        "radarr.${cfg.domain}" = {
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
        "sonarr.${cfg.domain}" = {
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
        "bazarr.${cfg.domain}" = {
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
        "ollama.${cfg.domain}" = {
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
        "cockatrice.${cfg.domain}" = {
          extraConfig = ''
            import cors
            reverse_proxy localhost:4748
          '';
        };
      }
      else {}
    )
    // (
      if config.myNixOS.services.harmonia.enable
      then {
        "nix-store.${cfg.domain}" = {
          extraConfig = ''
            reverse_proxy localhost:5000
          '';
        };
      }
      else {}
    );
  services_with_protocol = builtins.listToAttrs (
    lib.lists.flatten (
      builtins.map (
        {
          value,
          name,
        }:
          builtins.map (proto: {
            name = "${proto}://${name}";
            value = value;
          })
          cfg.protocol
      ) (lib.attrsets.attrsToList services)
    )
  );
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
      default = (import ../../secrets.nix).domain;
      description = ''
        tld to use
      '';
    };
    protocol = lib.mkOption {
      type = lib.types.listOf (lib.types.enum ["http" "https"]);
      default = ["https" "http"];
      description = ''
        protocol to use
      '';
    };
  };
  config = {
    networking.firewall.allowedTCPPorts = [80 443];
    services.caddy = {
      enable = true;
      email = (import ../../secrets.nix).email;
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
        // services_with_protocol;
    };
  };
}
