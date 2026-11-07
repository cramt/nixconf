# `<port>.t3.<domain>` reaches `localhost:<port>` on the T3 Code host, behind
# the authelia passkey. T3's preview renders a remote environment's dev server
# in a Chromium on that host, so the tab's URL is the host's own
# `http://localhost:<port>`, and "open in system browser" hands exactly that to
# the client machine, where nothing is listening. Upstream has no setting for
# it: the client's resolver throws "needs the planned authenticated preview
# gateway" (apps/web/src/browser/browserTargetResolver.ts). This is that
# gateway, by hand. Drop it once upstream ships theirs.
#
# The other fleet servers get the same through luna (`<port>.t3-<host>`, see
# t3code-fleet.nix): luna's caddy passes the passkey gate and hands the request
# to that host's preview gateway, which serves it from its own localhost.
#
# HTTPS rather than the LAN port, because a dev server on `http://<lan-ip>` is
# not a secure context: OPFS, SharedArrayBuffer and cross-origin isolation are
# all off there.
#
# Every HTTP service on the host is on some port, so this gates all of them
# behind the passkey, not only dev servers. Caddy's admin API is the exception:
# reaching it would rewrite caddy itself, the passkey gate included.
#
# Certificates are on-demand, one per port the first time it's opened, because
# a wildcard cert needs a DNS-01 challenge and with it a Cloudflare token on
# the host. The `ask` endpoint keeps that to names these vhosts would serve.
{ ... }: {
  flake.nixosModules."services.t3code-ports" = { config, lib, ... }:
  let
    cfg = config.myNixOS.services.t3code;
    domain = config.myNixOS.services.caddy.domain;
    askPort = config.port-selector.ports.t3code-ports-ask;
    autheliaPort = config.port-selector.ports.authelia;
    # Caddy's admin listener, which only ever binds loopback.
    caddyAdminPort = "2019";
    portPattern = "^[1-9][0-9]{0,4}$";
    hosts = cfg.previewHosts;

    vhost = host: gateway: let
      # Labels count from the right, so the one left of `host` is the port.
      portLabel = "{labels.${toString (lib.length (lib.splitString "." host))}}";
    in {
      # The `https://` spelling is what caddy.subdomains reads, which gives
      # `*.<subdomain>` its A record in infra/dns.nix.
      name = "https://*.${host}";
      value.extraConfig = ''
        tls {
          on_demand
        }
        @port vars_regexp ${portLabel} ${portPattern}
        @admin vars ${portLabel} ${caddyAdminPort}
        handle @admin {
          respond 404
        }
        handle @port {
          forward_auth localhost:${toString autheliaPort} {
            uri /api/authz/forward-auth
            copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
          }
          # Dev servers refuse unknown Host headers (Vite's allowedHosts),
          # and they were started expecting to be localhost. A remote
          # gateway routes on this Host's port.
          reverse_proxy ${if gateway == null then "localhost:${portLabel}" else gateway} {
            header_up Host localhost:${portLabel}
          }
        }
        handle {
          respond 404
        }
      '';
    };
  in {
    options.myNixOS.services.t3code = {
      portsSubdomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "t3";
        description = ''
          Serve `<port>.<portsSubdomain>.<domain>` as `localhost:<port>`, behind
          the authelia passkey, so a T3 preview's localhost URL has an address
          another machine can open.
        '';
      };
      previewHosts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.nullOr lib.types.str);
        default = {};
        internal = true;
        description = ''
          `<port>.<name>` served here → the preview gateway (`host:port`) that
          answers for it, or null for this host's own localhost.
        '';
      };
    };

    config = lib.mkMerge [
      (lib.mkIf (cfg.enable && cfg.portsSubdomain != null) {
        myNixOS.services.t3code.previewHosts."${cfg.portsSubdomain}.${domain}" = null;
      })

      (lib.mkIf (hosts != {}) {
        assertions = [
          {
            assertion = config.myNixOS.services.authelia.enable;
            message = "myNixOS.services.t3code preview hosts gate every port behind authelia, which is disabled.";
          }
        ];

        port-selector.auto-assign = [ "t3code-ports-ask" ];

        services.caddy.globalConfig = ''
          on_demand_tls {
            ask http://127.0.0.1:${toString askPort}/
          }
        '';

        services.caddy.virtualHosts = {
          "http://127.0.0.1:${toString askPort}".extraConfig = ''
            bind 127.0.0.1
            @served vars_regexp {query.domain} ^[1-9][0-9]{0,4}\.(${lib.concatMapStringsSep "|" lib.escapeRegex (lib.attrNames hosts)})$
            respond @served 200
            respond 404
          '';
        } // lib.mapAttrs' vhost hosts;
      })
    ];
  };
}
