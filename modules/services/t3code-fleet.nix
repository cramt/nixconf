# The T3 Code servers as one fleet (myLib/t3code-fleet.nix): each one links to
# every other, so an agent on any of them can launch and drive threads on the
# rest. The links themselves are my-nixpkgs' services.t3code.linkedEnvironments;
# this adds the routing that makes the non-hub servers linkable at all:
#  - on the hub: `t3-<host>` → `<host>:3773`, and `<port>.t3-<host>` (behind
#    the passkey) → that host's preview gateway
#  - on the others: the preview gateway, open to the hub only
{ ... }: {
  flake.nixosModules."services.t3code-fleet" = { config, lib, ... }:
  let
    fleet = import ../../myLib/t3code-fleet.nix;
    cfg = config.myNixOS.services.t3code;
    self = config.networking.hostName;
    domain = config.myNixOS.services.caddy.domain;
    isHub = self == fleet.hub;
    gatewayPort = toString fleet.previewGatewayPort;
    others = lib.filterAttrs (name: _: name != self) fleet.servers;
    remotes = lib.filterAttrs (name: _: name != fleet.hub) fleet.servers;
  in {
    config = lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.enable == fleet.servers ? ${self};
            message = "myNixOS.services.t3code.enable and myLib/t3code-fleet.nix disagree about ${self}: a server is linked to by every other one, so list it there (or drop it).";
          }
          {
            assertion = isHub && cfg.enable -> cfg.subdomain == fleet.servers.${self};
            message = "myLib/t3code-fleet.nix names the hub's vhost ${fleet.servers.${fleet.hub}}, but its myNixOS.services.t3code.subdomain says otherwise.";
          }
        ];
      }

      (lib.mkIf cfg.enable {
        # What fleet.url points peers at. The vhost itself only gates on the
        # tailnet; trustTailnet adds the proxy, signing tailnet clients in
        # with the shared secret so they skip pairing. Peers still link with
        # their own tokens, which it passes through untouched.
        myNixOS.tailnet-https.ports."443" = "";
        services.t3code.trustTailnet = {
          enable = true;
          virtualHost = "https://${config.myNixOS.tailnet-https.name}:443";
          # luna is the tailnet member running other people's code (service
          # users, containers): anything there dialing a server's tailnet
          # name would get a session as Alex. Its own agents link with tokens.
          excludeRanges = map (a: if lib.hasInfix ":" a then "${a}/128" else "${a}/32")
            (import ../../myLib/site.nix).luna_tailnet_addresses;
        };
        services.t3code.linkedEnvironments.peers = lib.mapAttrs (name: _: {
          urls = [ (fleet.url name) ];
          pairingCodeFile = config.myNixOS.secrets.t3codeSharedSecret.path;
          # All of them are Alex's own machines, and agents already deploy luna.
          access = "full-access";
        }) others;
      })

      (lib.mkIf (cfg.enable && isHub) {
        # No passkey on the server vhosts: like the hub's own, t3code's
        # pairing is the boundary, and peers can't get through a login portal.
        services.caddy.virtualHosts = lib.mapAttrs' (name: sub:
          lib.nameValuePair "https://${sub}.${domain}" {
            extraConfig = ''
              reverse_proxy ${name}:${toString config.services.t3code.port}
            '';
          }) remotes;
        myNixOS.services.t3code.previewHosts = lib.mapAttrs' (name: sub:
          lib.nameValuePair "${sub}.${domain}" "${name}:${gatewayPort}") remotes;
      })

      # Serves the hub's `<port>.t3-<host>` from this host's localhost, picking
      # the port off the Host header the hub sets (localhost:<port>). Plain
      # http on the LAN, so it only takes the hub, which has already checked
      # the passkey. Dev servers mostly bind loopback, hence a proxy here
      # rather than the hub dialing each port.
      (lib.mkIf (cfg.enable && !isHub) {
        port-selector.set-ports.${gatewayPort} = "t3code-preview-gateway";

        services.caddy = {
          enable = true;
          virtualHosts."http://:${gatewayPort}".extraConfig = ''
            @blocked vars {http.request.port} 2019 ${gatewayPort}
            handle @blocked {
              respond 404
            }
            @port vars_regexp {http.request.port} ^[1-9][0-9]{0,4}$
            handle @port {
              reverse_proxy localhost:{http.request.port}
            }
            respond 404
          '';
        };

        networking.firewall.extraCommands = ''
          iptables -A nixos-fw -p tcp -s ${fleet.hubAddress} --dport ${gatewayPort} -j nixos-fw-accept
        '';
        networking.firewall.extraStopCommands = ''
          iptables -D nixos-fw -p tcp -s ${fleet.hubAddress} --dport ${gatewayPort} -j nixos-fw-accept || true
        '';
      })
    ];
  };
}
