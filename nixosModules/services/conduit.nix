{
  pkgs,
  config,
  ...
}: let
  secrets = import ../../secrets.nix;
  shared_secret = secrets.shared_matrix_secret;
  turnDomain = "turn.${secrets.domain}";
  turnMin = 49000;
  turnMax = 50000;
  cloudflareCredentials = pkgs.writeText ''cloudflare_creds.env'' ''
    CLOUDFLARE_EMAIL=${secrets.email}
    CLOUDFLARE_API_KEY=${secrets.cloudflare_api_key}
  '';
in {
  config = {
    # tls
    security.acme.acceptTerms = true;
    security.acme.certs.${turnDomain} = {
      reloadServices = ["coturn"];
      group = "turnserver";
      email = secrets.email;
      dnsProvider = "cloudflare";
      environmentFile = cloudflareCredentials;
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
    services = {
      matrix-conduit = {
        enable = true;
        settings.global = {
          server_name = "matrix.${secrets.domain}";
          turn_uris = ["turn:${turnDomain}:3478?transport=udp" "turn:${turnDomain}:3478?transport=tcp"];
          turn_secret = shared_secret;
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
        static-auth-secret = shared_secret;
        realm = turnDomain;
        cert = "${config.security.acme.certs.${turnDomain}.directory}/full.pem";
        pkey = "${config.security.acme.certs.${turnDomain}.directory}/key.pem";
      };
    };
  };
}
