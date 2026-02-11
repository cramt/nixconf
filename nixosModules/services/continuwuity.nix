{
  config,
  ...
}: let
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

    myNixOS.services.caddy.serviceMap = {
      matrix = {
        port = 6167;
      };
    };

    # secret env file for registration_token, turn_secret, etc.
    systemd.services.continuwuity.serviceConfig.EnvironmentFile = [
      config.services.onepassword-secrets.secretPaths.matrixSecretEnv
    ];

    services = {
      matrix-continuwuity = {
        enable = true;
        settings.global = {
          server_name = "matrix.${site.domain}";
          turn_uris = ["turn:${turnDomain}:3478?transport=udp" "turn:${turnDomain}:3478?transport=tcp"];
          allow_registration = true;
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
