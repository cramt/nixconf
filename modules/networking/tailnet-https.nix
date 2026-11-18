# HTTPS on the host's own tailnet name, <host>.<tailnet>.ts.net, for services
# only fleet members should reach.
#
# The cert is Tailscale's: caddy asks the local tailscaled for it (HTTPS is
# switched on for the tailnet in infra/tailscale.nix), so there's no ACME
# client or DNS credential on the host.
#
# Every vhost here answers tailnet source addresses only. That isn't
# redundant with the firewall: on luna 443 is public, and anyone can send
# this SNI to it.
{ ... }: {
  flake.nixosModules."networking.tailnet-https" = { config, lib, ... }:
  let
    cfg = config.myNixOS.tailnet-https;
    site = import ../../myLib/site.nix;
  in {
    options.myNixOS.tailnet-https = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "${config.networking.hostName}.${site.tailnet_domain}";
        readOnly = true;
        description = "This host's MagicDNS name, which the cert is for.";
      };
      ports = lib.mkOption {
        type = lib.types.attrsOf lib.types.lines;
        default = {};
        example = { "443" = "reverse_proxy localhost:3773"; };
        description = ''
          Caddy directives per HTTPS port on `name`. Setting any enables the
          vhosts. Requests from outside the tailnet get a 403 before these run.
        '';
      };
    };

    config = lib.mkIf (cfg.ports != {}) {
      assertions = [
        {
          assertion = config.myNixOS.services.tailscale.enable;
          message = "myNixOS.tailnet-https gets its cert from tailscaled; enable myNixOS.services.tailscale.";
        }
      ];

      services.tailscale.permitCertUid = config.services.caddy.user;

      services.caddy = {
        enable = true;
        virtualHosts = lib.mapAttrs' (port: directives:
          lib.nameValuePair "https://${cfg.name}:${port}" {
            # Explicit rather than caddy's implicit *.ts.net handling, so a
            # global issuer added to caddy later can't take these over.
            extraConfig = ''
              tls {
                get_certificate tailscale
              }
              @offTailnet not remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48
              respond @offTailnet 403
              ${directives}
            '';
          })
          cfg.ports;
      };
      systemd.services.caddy = {
        after = ["tailscaled.service"];
        wants = ["tailscaled.service"];
      };
    };
  };
}
