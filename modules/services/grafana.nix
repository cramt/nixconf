# Dashboards over the fleet prometheus, behind the same authelia passkey as the
# other admin UIs. Grafana trusts the Remote-User header caddy copies from
# authelia (auth.proxy), so the passkey is the only login, and that user is the
# grafana admin. Everything (datasource, dashboards) is provisioned read-only
# from Nix; edits in the UI don't persist.
{...}: {
  flake.nixosModules."services.grafana" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.grafana;
    caddyDomain = config.myNixOS.services.caddy.domain;
    port = config.port-selector.ports.grafana;
    secretKey = "${config.services.grafana.dataDir}/secret_key";

    dashboards = import ./_grafana/dashboards.nix {
      inherit lib;
      domain = caddyDomain;
    };
    dashboardDir = pkgs.linkFarm "grafana-dashboards" (lib.mapAttrsToList (name: d: {
        name = "${name}.json";
        path = pkgs.writeText "${name}.json" (builtins.toJSON d);
      })
      dashboards);
  in {
    options.myNixOS.services.grafana = {
      enable = lib.mkEnableOption "myNixOS.services.grafana";
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "grafana";
        description = ''
          Vhost. Gets its A record from caddy.subdomains.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.myNixOS.services.authelia.enable;
          message = "myNixOS.services.grafana trusts authelia's Remote-User header, so it needs myNixOS.services.authelia.";
        }
        {
          assertion = config.myNixOS.services.metrics.server.enable;
          message = "myNixOS.services.grafana reads the local prometheus, so it needs myNixOS.services.metrics.server.";
        }
      ];

      port-selector.auto-assign = ["grafana"];

      # Grafana only encrypts datasource secrets with this, and the provisioned
      # prometheus has none, so a per-host random key beats a 1Password item.
      systemd.services.grafana.preStart = lib.mkBefore ''
        if [ ! -s ${secretKey} ]; then
          (umask 077; ${pkgs.openssl}/bin/openssl rand -hex 32 > ${secretKey})
        fi
      '';

      services.grafana = {
        enable = true;
        settings = {
          server = {
            # Only caddy may reach it: auth.proxy trusts whoever can set the
            # header.
            http_addr = "127.0.0.1";
            http_port = port;
            domain = "${cfg.subdomain}.${caddyDomain}";
            root_url = "https://${cfg.subdomain}.${caddyDomain}/";
          };
          security = {
            secret_key = "$__file{${secretKey}}";
            # The authelia user lands as the server admin instead of beside it.
            admin_user = config.myNixOS.services.authelia.user.name;
            admin_email = config.myNixOS.services.authelia.user.email;
            # Unused (there's no login form), but grafana creates the admin with
            # one, and the default is "admin".
            admin_password = "$__file{${secretKey}}";
            cookie_secure = true;
          };
          "auth.proxy" = {
            enabled = true;
            header_name = "Remote-User";
            header_property = "username";
            headers = "Email:Remote-Email Name:Remote-Name";
            auto_sign_up = true;
            whitelist = "127.0.0.1, ::1";
          };
          auth.disable_login_form = true;
          "auth.basic".enabled = false;
          users = {
            allow_sign_up = false;
            auto_assign_org_role = "Admin";
          };
          analytics = {
            reporting_enabled = false;
            check_for_updates = false;
            check_for_plugin_updates = false;
            feedback_links_enabled = false;
          };
        };
        provision = {
          enable = true;
          datasources.settings = {
            apiVersion = 1;
            datasources = [
              {
                name = "Prometheus";
                type = "prometheus";
                # No `uid`. Grafana's first start can create this under a random
                # uid, and from then on every start fails with "data source not
                # found" trying to move it to the pinned one -- luna crashlooped
                # on exactly that (https://github.com/grafana/grafana/issues/110740).
                # Matching by name survives either state. Pin a uid again once
                # that closes; dashboards would then reference it by uid instead
                # of relying on it being the default.
                url = "http://127.0.0.1:${toString config.port-selector.ports.prometheus}";
                isDefault = true;
                editable = false;
                # Lets $__rate_interval know samples are this far apart.
                jsonData.timeInterval = config.myNixOS.services.metrics.server.scrapeInterval;
              }
            ];
          };
          dashboards.settings = {
            apiVersion = 1;
            providers = [
              {
                name = "nixconf";
                options.path = dashboardDir;
                allowUiUpdates = false;
                disableDeletion = true;
              }
            ];
          };
        };
      };

      myNixOS.services.caddy.serviceMap.${cfg.subdomain} = {
        inherit port;
        forward-auth = true;
      };
    };
  };
}
