{config, ...}: let
  site = import ../../site.nix;
  turnDomain = "turn.${site.domain}";
  turnMin = 49000;
  turnMax = 50000;
in {
  config = {
    security.acme.acceptTerms = true;
    security.acme.certs.${turnDomain} = {
      reloadServices = ["coturn"];
      group = "turnserver";
      email = site.email;
      dnsProvider = "cloudflare";
      environmentFile = config.services.onepassword-secrets.secretPaths.cloudflareCredsEnv;
    };

    networking.firewall = {
      allowedUDPPortRanges = [
        {
          from = turnMin;
          to = turnMax;
        }
      ];
      allowedUDPPorts = [3478 5349];
      allowedTCPPorts = [3478 5349];
    };

    port-selector = {
      set-ports."3478" = "matrix_turn_udp";
      additional-blocked-port-ranges = [
        {
          from = turnMin;
          to = turnMax;
        }
      ];
    };

    services.caddy.virtualHosts."matrix.cramt.dk".extraConfig = ''
      handle /.well-known/matrix/server {
        header Content-Type application/json
        respond `{"m.server":"matrix.cramt.dk:443"}` 200
      }

      handle /.well-known/matrix/client {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond `{"m.homeserver":{"base_url":"https://matrix.cramt.dk"}}` 200
      }

      handle /.well-known/matrix/support {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond `{"contacts":[{"matrix_id":"@cramt:matrix.cramt.dk","role":"m.role.admin"}]}` 200
      }

      handle /_matrix/* {
        reverse_proxy unix//run/continuwuity/continuwuity.sock
      }

      handle {
        respond "Not Found" 404
      }
    '';

    # secret env file for registration_token, turn_secret, etc.
    systemd.services.continuwuity.serviceConfig.EnvironmentFile = [
      config.services.onepassword-secrets.secretPaths.matrixSecretEnv
    ];

    users.users.caddy.extraGroups = ["continuwuity"];

    services = {
      matrix-continuwuity = {
        enable = true;
        settings.global = {
          server_name = "matrix.${site.domain}";
          address = null;
          unix_socket_path = "/run/continuwuity/continuwuity.sock";
          unix_socket_perms = 660;
          turn_uris = ["turn:${turnDomain}:3478?transport=udp" "turn:${turnDomain}:3478?transport=tcp"];
          allow_registration = false;
          admins_list = ["@cramt:matrix.cramt.dk"];
          allow_federation = true;
          trusted_servers = ["matrix.org" "beeper.com" "lix.systems"];
          allow_announcements_check = false;
        };
      };

      coturn = {
        enable = true;
        no-cli = true;
        no-tcp-relay = true;
        min-port = turnMin;
        max-port = turnMax;
        use-auth-secret = true;
        static-auth-secret-file = config.services.onepassword-secrets.secretPaths.matrixSharedSecret;
        realm = turnDomain;
        cert = "${config.security.acme.certs.${turnDomain}.directory}/full.pem";
        pkey = "${config.security.acme.certs.${turnDomain}.directory}/key.pem";
      };
    };
  };
}
