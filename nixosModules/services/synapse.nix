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
    services = {
      matrix-synapse = {
        enable = true;
        withJemalloc = true;
        extraConfigFiles = [
          config.services.onepassword-secrets.secretPaths.synapseExtraConfig
        ];
        settings = {
          enable_metrics = true;
          enable_registration = false;
          allow_guest_access = false;
          dynamic_thumbnails = true;
          server_name = "matrix.${site.domain}";
          turn_uris = ["turn:${turnDomain}:3478?transport=udp" "turn:${turnDomain}:3478?transport=tcp"];
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
        static-auth-secret-file = config.services.onepassword-secrets.secretPaths.matrixSharedSecret;
        realm = turnDomain;
        cert = "${config.security.acme.certs.${turnDomain}.directory}/full.pem";
        pkey = "${config.security.acme.certs.${turnDomain}.directory}/key.pem";
      };
    };
  };
}
