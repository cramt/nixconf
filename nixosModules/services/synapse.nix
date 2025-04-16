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
    myNixOS.services.postgres = {
      enable = true;
      applicationUsers = [
        {
          name = "matrix-synapse";
        }
      ];
    };
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
      matrix-synapse = {
        enable = true;
        withJemalloc = true;
        settings = {
          enable_metrics = true;
          enable_registration = false;
          allow_guest_access = false;
          dynamic_thumbnails = true;
          server_name = "matrix.${secrets.domain}";
          registration_shared_secret = shared_secret;
          turn_uris = ["turn:${turnDomain}:3478?transport=udp" "turn:${turnDomain}:3478?transport=tcp"];
          turn_shared_secret = shared_secret;
          turn_user_lifetime = "1h";
          listeners = [
            {
              bind_addresses = ["0.0.0.0"];
              port = 8448;
              resources = [
                {
                  compress = false;
                  names = ["client"];
                }
              ];
              tls = false;
              type = "http";
              x_forwarded = false;
            }
          ];
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
