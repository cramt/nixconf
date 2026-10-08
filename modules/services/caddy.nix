{...}: {
  flake.nixosModules."services.caddy" = {
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
      // (lib.attrsets.mapAttrs' (name: {
          port,
          basic-auth,
          forward-auth,
          reverse-proxy-config,
          ungated-paths,
          ...
        }: let
          upstream = "http://localhost:${builtins.toString port}";
          gated = ''
            ${lib.optionalString forward-auth ''
              forward_auth localhost:${builtins.toString config.port-selector.ports.authelia} {
                uri /api/authz/forward-auth
                copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
              }
            ''}
            reverse_proxy ${upstream} {
              ${reverse-proxy-config}
            }
          '';
        in {
          name = "${name}.${cfg.domain}";
          value = {
            extraConfig = ''
              import cors
              request_body {
                  max_size 5GB
              }
              ${
                if basic-auth == null
                then ""
                else ''
                  basic_auth {
                    ${basic-auth.username} ${basic-auth.hashed-password}
                  }
                ''
              }
              ${
                if ungated-paths == []
                then gated
                else ''
                  @ungated path ${lib.concatStringsSep " " ungated-paths}
                  handle @ungated {
                    reverse_proxy ${upstream}
                  }
                  handle {
                    ${gated}
                  }
                ''
              }
            '';
          };
        })
        cfg.serviceMap)
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
    subdomainOf = vhost: let
      m = builtins.match "([a-z]+://)?(.+)\\.${lib.escapeRegex cfg.domain}" vhost;
    in
      if m == null
      then null
      else builtins.elemAt m 1;
  in {
    options.myNixOS.services.caddy = {
      enable = lib.mkEnableOption "myNixOS.services.caddy";
      subdomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          Every subdomain of `domain` this host's caddy serves. Read back from
          the rendered virtualHosts, so vhosts added outside serviceMap count
          too. infra/dns.nix gives each one an A record.
        '';
      };
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
        default = (import ../../myLib/site.nix).domain;
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
      serviceMap = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            port = lib.mkOption {
              type = lib.types.int;
            };
            basic-auth = lib.mkOption {
              default = null;
              type = lib.types.nullOr (lib.types.submodule {
                options = {
                  username = lib.mkOption {
                    type = lib.types.str;
                  };
                  hashed-password = lib.mkOption {
                    type = lib.types.str;
                  };
                };
              });
            };
            forward-auth = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Put this vhost behind the myNixOS.services.authelia passkey portal.
              '';
            };
            ungated-paths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              example = ["/v1/*"];
              description = ''
                Caddy path matchers that skip forward-auth and
                reverse-proxy-config, for clients that can't do a browser
                login. The upstream must authenticate these itself: they are a
                hole in the passkey gate.
              '';
            };
            reverse-proxy-config = lib.mkOption {
              type = lib.types.lines;
              default = "";
              description = ''
                Extra directives inside this vhost's reverse_proxy block.
              '';
            };
          };
        });
        default = {};
        description = ''
          services to map
        '';
      };
    };
    config = lib.mkMerge [
      {
        myNixOS.services.caddy.subdomains = lib.unique (lib.sort lib.lessThan (
          lib.filter (s: s != null) (map subdomainOf (lib.attrNames config.services.caddy.virtualHosts))
        ));
      }
      (lib.mkIf cfg.enable {
        # Without the portal, forward_auth would point at a port nothing listens
        # on and every gated vhost would 502 -- fail the build instead.
        assertions = [
          {
            assertion =
              config.myNixOS.services.authelia.enable
              || !(lib.any (s: s.forward-auth) (lib.attrValues cfg.serviceMap));
            message = "caddy.serviceMap has forward-auth entries but myNixOS.services.authelia is disabled.";
          }
        ];
        networking.firewall.allowedTCPPorts = [80 443];
        # Served by caddy's admin API, which only ever listens on loopback.
        myNixOS.services.metrics.localJobs.caddy = {
          port = 2019;
          # per_host takes the raw Host header, so a client that spells out
          # `:443` splits one vhost into two series and undercounts it.
          extraConfig.metric_relabel_configs = [
            {
              source_labels = ["host"];
              regex = "(.+):443";
              target_label = "host";
              replacement = "$1";
            }
          ];
        };
        services.caddy = {
          enable = true;
          email = (import ../../myLib/site.nix).email;
          # per_host labels every request series with its vhost, which is what
          # "is anyone actually using <service>" comes down to on this box.
          globalConfig = ''
            debug
            metrics {
              per_host
            }
          '';
          virtualHosts =
            {
              "(cors)" = {
                extraConfig = ''

                  @cors_preflight method OPTIONS

                  header {
                    ?Access-Control-Allow-Origin "*"
                    ?Access-Control-Expose-Headers "Authorization"
                    ?Access-Control-Allow-Headers *
                    ?Access-Control-Allow-Credentials "true"
                    ?Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE"
                    ?Access-Control-Max-Age "3600"
                  }

                  handle @cors_preflight {
                    header {
                      ?Access-Control-Allow-Origin "*"
                      Access-Control-Expose-Headers "Authorization"
                      Access-Control-Allow-Headers *
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
      })
    ];
  };
}
