# HTTPS on the host's own tailnet name, <host>.ts.cramt.dk, for services only
# fleet members should reach.
#
# headscale can't issue certs the way Tailscale's control server does, so
# `tailscale cert` / `tailscale serve` HTTPS don't work here. Instead lego gets
# a real Let's Encrypt cert through a Cloudflare DNS-01 challenge (the name
# only resolves inside the tailnet, so HTTP-01 can't reach it), and caddy
# serves it.
#
# Every vhost here answers tailnet source addresses only. That isn't
# redundant with the firewall: on luna 443 is public, and anyone can send
# this SNI to it.
{ ... }: {
  flake.nixosModules."networking.tailnet-https" = { config, lib, ... }:
  let
    cfg = config.myNixOS.tailnet-https;
    site = import ../../myLib/site.nix;
    secrets = config.myNixOS.secrets;
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
          cert and the vhosts. Requests from outside the tailnet get a 403
          before these run.
        '';
      };
    };

    config = lib.mkIf (cfg.ports != {}) {
      myNixOS.secrets = {
        cloudflareEmail = {
          reference = "op://Homelab/Infrastructure/email";
          services = ["acme-${cfg.name}"];
        };
        cloudflareApiKey = {
          reference = "op://Homelab/Cloudflare/apiKey";
          services = ["acme-${cfg.name}"];
        };
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = site.email;
        certs.${cfg.name} = {
          dnsProvider = "cloudflare";
          # The system resolver is MagicDNS, which owns ts.cramt.dk and never
          # sees the TXT record lego is waiting for. Ask Cloudflare directly.
          dnsResolver = "1.1.1.1:53";
          credentialFiles = {
            CLOUDFLARE_EMAIL_FILE = secrets.cloudflareEmail.path;
            CLOUDFLARE_API_KEY_FILE = secrets.cloudflareApiKey.path;
          };
          group = config.services.caddy.group;
          reloadServices = ["caddy.service"];
        };
      };
      systemd.services."acme-${cfg.name}" = {
        after = ["op-secrets.service"];
        wants = ["op-secrets.service"];
      };

      services.caddy = {
        enable = true;
        virtualHosts = lib.mapAttrs' (port: directives:
          lib.nameValuePair "https://${cfg.name}:${port}" {
            # Not a hand-written `tls` line: this also orders caddy after the
            # cert unit, which puts a self-signed placeholder down first, so
            # the very first reload doesn't fail on a missing file.
            useACMEHost = cfg.name;
            extraConfig = ''
              @offTailnet not remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48
              respond @offTailnet 403
              ${directives}
            '';
          })
          cfg.ports;
      };
    };
  };
}
