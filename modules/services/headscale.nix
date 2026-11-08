# The fleet's tailnet coordinator. Clients are myNixOS.services.tailscale.
#
# Headscale can't be handed a pre-auth key, it only mints its own, so the one
# non-declarative step is the shared join key: mint it here once and park it in
# op://Homelab/Headscale/preauthKey (the tailscale module says how). The host
# running this joins with a key it mints locally instead, so it never depends on
# that 1Password item existing.
{ ... }: {
  flake.nixosModules."services.headscale" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.headscale;
    site = import ../../myLib/site.nix;
    ports = config.port-selector.ports;
    headscale = lib.getExe config.services.headscale.package;
  in {
    options.myNixOS.services.headscale = {
      enable = lib.mkEnableOption "myNixOS.services.headscale";
      localKeyFile = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "/run/headscale-local-key/key";
        description = ''
          A fresh single-use pre-auth key for this host's own tailscaled,
          written by headscale-local-key.service.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.myNixOS.services.caddy.enable;
          message = "myNixOS.services.headscale is served through caddy; enable myNixOS.services.caddy.";
        }
      ];

      port-selector.auto-assign = ["headscale" "headscale-metrics" "headscale-grpc"];

      services.headscale = {
        enable = true;
        address = "127.0.0.1";
        port = ports.headscale;
        settings = {
          server_url = site.headscale_url;
          # The defaults (9090, 50443) collide with whatever else claims them;
          # 9090 is prometheus on luna.
          metrics_listen_addr = "127.0.0.1:${toString ports.headscale-metrics}";
          grpc_listen_addr = "127.0.0.1:${toString ports.headscale-grpc}";
          dns = {
            magic_dns = true;
            base_domain = site.tailnet_domain;
            # Keep each host's own resolver (the router, for LAN names of hosts
            # that aren't on the tailnet); tailscale only adds the tailnet zone.
            override_local_dns = false;
          };
          # No policy file: a single-owner tailnet, every node reaches every node.
        };
      };

      services.caddy.virtualHosts."https://${lib.removePrefix "https://" site.headscale_url}".extraConfig = ''
        reverse_proxy localhost:${toString ports.headscale}
      '';

      # Every node belongs to one user; headscale has no option to declare it.
      systemd.services.headscale-local-key = {
        description = "Mint a pre-auth key for this host's own tailscaled";
        after = ["headscale.service"];
        requires = ["headscale.service"];
        wantedBy = ["multi-user.target"];
        path = [pkgs.jq];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = config.services.headscale.user;
          Group = config.services.headscale.group;
          RuntimeDirectory = "headscale-local-key";
          RuntimeDirectoryMode = "0700";
          # tailscaled-autoconnect runs as root and reads the key.
          RuntimeDirectoryPreserve = "yes";
        };
        script = ''
          # headscale.service is "up" before its socket answers.
          for _ in $(seq 30); do
            ${headscale} users list -o json >/dev/null 2>&1 && break
            sleep 1
          done
          if ! ${headscale} users list -o json | jq -e '.[] | select(.name == "fleet")' >/dev/null; then
            ${headscale} users create fleet
          fi
          id=$(${headscale} users list -o json | jq -r '.[] | select(.name == "fleet") | .id')
          ${headscale} preauthkeys create --user "$id" --expiration 1h -o json \
            | jq -r .key > ${cfg.localKeyFile}
        '';
      };
    };
  };
}
