# Paseo daemon — self-hosted orchestrator that runs coding agents on this host,
# so you can offload agent work from a laptop to a server. Wraps the upstream
# flake's nixosModule (see the `paseo` input in flake.nix).
#
# Runs as a real login user (not the isolated `paseo` system user) so the agents
# it spawns inherit that user's dev environment: git, ssh keys, and the agent
# CLIs (claude, codex) from their home-manager profile. The upstream module
# auto-enables `inheritUserEnvironment` whenever `user` isn't the default.
{ inputs, ... }: {
  flake.nixosModules."services.paseo" = { config, lib, ... }:
  let
    cfg = config.myNixOS.services.paseo;
    caddyCfg = config.myNixOS.services.caddy;
    # port-selector hashes the service name to a stable loopback port; Caddy
    # fronts it, so the exact number is an internal detail.
    port = config.port-selector.ports.paseo;
  in {
    imports = [ inputs.paseo.nixosModules.default ];

    options.myNixOS.services.paseo = {
      enable = lib.mkEnableOption "myNixOS.services.paseo";
      user = lib.mkOption {
        type = lib.types.str;
        default = "paseo";
        description = ''
          User the daemon runs as. Set to a real login user (e.g. "cramt") so
          spawned agents get that user's git/ssh and agent CLIs. Leave as the
          default "paseo" system user for an isolated, tool-less daemon.
        '';
      };
      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Address to bind. Left on loopback when fronted by Caddy (see
          `subdomain`). Use "0.0.0.0" only for direct LAN access without a proxy.
        '';
      };
      openFirewall = lib.mkEnableOption "opening the daemon port in the firewall";
      subdomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "paseo";
        description = ''
          When set, front the daemon with this host's Caddy at
          `<subdomain>.<caddy domain>` (TLS + reverse proxy) and add that
          hostname to the daemon's allow-list (its DNS-rebinding protection,
          since Caddy forwards the original Host header). Requires
          `myNixOS.services.caddy.enable` on the same host, plus a DNS record
          for the subdomain (see infra/main.tf).
        '';
      };
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        # "use the port selector i have" — let it assign the loopback port
        # instead of pinning one.
        port-selector.auto-assign = [ "paseo" ];

        services.paseo = {
          enable = true;
          inherit (cfg) user listenAddress openFirewall;
          inherit port;
          # No third-party relay: access is via Caddy on the LAN/domain, so agent
          # traffic never leaves your infra. Flip on for control from off-network.
          relay.enable = false;
        };
      }
      (lib.mkIf (cfg.subdomain != null) {
        myNixOS.services.caddy.serviceMap.${cfg.subdomain}.port = port;
        services.paseo.hostnames = [ "${cfg.subdomain}.${caddyCfg.domain}" ];
      })
    ]);
  };
}
