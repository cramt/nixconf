# Paseo daemon — self-hosted orchestrator that runs coding agents on this host,
# so you can offload agent work from a laptop to a server.
#
# Runs as a real login user's `systemd --user` service (not a system unit), so
# the daemon lives in a genuine user session and the agents it spawns inherit
# that user's home-manager environment: git, ssh keys, and the agent CLIs
# (claude, codex). Upstream's nixosModule only ships a *system* service, so we
# don't use it — we hand-roll the user unit from `inputs.paseo.packages`.
{ inputs, ... }: {
  flake.nixosModules."services.paseo" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.services.paseo;
    caddyCfg = config.myNixOS.services.caddy;
    # port-selector hashes the service name to a stable loopback port; Caddy
    # fronts it, so the exact number is an internal detail.
    port = config.port-selector.ports.paseo;
    paseoPkg = inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.default;
    dataDir = "/home/${cfg.user}/.paseo";
    # Host header allow-list (DNS-rebinding protection). Caddy forwards the
    # original Host, so the fronting subdomain must be allowed.
    hostnames = lib.optional (cfg.subdomain != null) "${cfg.subdomain}.${caddyCfg.domain}";
  in {
    options.myNixOS.services.paseo = {
      enable = lib.mkEnableOption "myNixOS.services.paseo";
      user = lib.mkOption {
        type = lib.types.str;
        default = "cramt";
        description = ''
          Real login user whose `systemd --user` manager runs the daemon. Its
          home-manager profile (git/ssh, claude/codex CLIs) is what spawned
          agents inherit. Must be one of this host's home-users.
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
        # Pin to paseo's canonical port so the `paseo` CLI (which defaults to
        # 6776) reaches this daemon without extra flags. Loopback-only; Caddy
        # fronts it, so the number is otherwise an internal detail.
        port-selector.set-ports."6776" = "paseo";

        # Headless host: enable linger so the user's systemd manager (and the
        # daemon) come up at boot without an interactive login.
        users.users.${cfg.user}.linger = true;

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ port ];

        # The daemon as a per-user systemd unit, defined in the user's
        # home-manager (NixOS→HM bridge from modules/bundles/nixos-users.nix).
        # HM uses INI-style Unit/Service/Install sections, not NixOS
        # serviceConfig/wantedBy.
        home-manager.users.${cfg.user} = { ... }: {
          systemd.user.services.paseo = {
            Unit.Description = "Paseo - self-hosted daemon for AI coding agents";
            Install.WantedBy = [ "default.target" ];
            Service = {
              ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${dataDir}";
              # No third-party relay: access is via Caddy on the LAN/domain, so
              # agent traffic never leaves your infra.
              ExecStart = "${paseoPkg}/bin/paseo-server --no-relay";
              # Daemon auth password via PASEO_PASSWORD (plaintext, hashed at
              # runtime by paseo). Sourced from opnix so it never lands in the
              # store. Without it the daemon accepts unauthenticated connections
              # — critical since the web UI below is internet-reachable through
              # Caddy. Read as this user, so opnix must own the file to them.
              EnvironmentFile = config.services.onepassword-secrets.secretPaths.paseoEnv;
              Environment = [
                "NODE_ENV=production"
                "PASEO_HOME=${dataDir}"
                "PASEO_LISTEN=${cfg.listenAddress}:${toString port}"
                # Serve the browser web UI. Off by default upstream — the daemon
                # is otherwise API/websocket only, so the domain 404s in a
                # browser. Exposed at https://<subdomain>.<domain>, gated by the
                # daemon password above.
                "PASEO_WEB_UI_ENABLED=true"
                # Explicit PATH so agent processes the daemon spawns find git/ssh
                # + the claude/codex CLIs. systemd --user does not reliably put
                # the per-user profile on PATH, so set it here.
                "PATH=/home/${cfg.user}/.nix-profile/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin"
              ] ++ lib.optional (hostnames != []) "PASEO_HOSTNAMES=${lib.concatStringsSep "," hostnames}";
              Restart = "on-failure";
              RestartSec = "5";
              # Graceful shutdown (server handles SIGTERM with a 10s timeout)
              KillSignal = "SIGTERM";
              TimeoutStopSec = "15";
            };
          };
        };
      }
      (lib.mkIf (cfg.subdomain != null) {
        myNixOS.services.caddy.serviceMap.${cfg.subdomain}.port = port;
      })
    ]);
  };
}
