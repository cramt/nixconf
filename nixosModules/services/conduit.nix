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
    # tls
    security.acme.acceptTerms = true;
    security.acme.certs.${turnDomain} = {
      reloadServices = ["coturn"];
      group = "turnserver";
      email = site.email;
      dnsProvider = "cloudflare";
      environmentFile = config.services.onepassword-secrets.secretPaths.cloudflareCredsEnv;
    };
    # turn server notwork config
    networking.firewall = {
      allowedUDPPortRanges = [
        {
          from = turnMin;
          to = turnMax;
        }
      ];
      allowedUDPPorts = [3478 5349];
      allowedTCPPortRanges = [];
      allowedTCPPorts = [3478 5349];
    };
    port-selector = {
      "3478" = "matrix_turn_udp";
      additional-blocked-port-ranges = [
        {
          from = turnMin;
          to = turnMax;
        }
      ];
    };
    services = {
      matrix-conduit = {
        enable = true;
        secretFile = config.services.onepassword-secrets.secretPaths.conduitSecretEnv;
        settings.global = {
          server_name = "matrix.${site.domain}";
          turn_uris = ["turn:${turnDomain}:3478?transport=udp" "turn:${turnDomain}:3478?transport=tcp"];
          allow_check_for_updates = false;
          allow_registration = true;
          database_backend = "rocksdb";
          registration_token = "yelliv";
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
