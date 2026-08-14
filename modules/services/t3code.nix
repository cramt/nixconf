# T3 Code server — self-hosted orchestrator that runs coding agents on this
# host, so agent work can be offloaded from a laptop to a server. Replaces the
# paseo daemon that used to hold this slot.
#
# Runs as a real login user's `systemd --user` service (not a system unit), so
# the server lives in a genuine user session and the agents it spawns inherit
# that user's home-manager environment: git, ssh keys, and the agent CLIs
# (claude, codex). Upstream's own `t3 service install` writes a user unit too,
# but it also installs a self-updating launcher under ~/.t3 — Nix owns the
# version here, so the unit is hand-rolled around `t3 serve` instead.
#
# Unlike paseo the server binds an interface directly rather than dialing out to
# a relay. It's bound on the LAN and the firewall port is opened; the one-time
# pairing token from `t3 pair` (see `just t3_pair`) is the capability that gets a
# client in, and unauthenticated requests are rejected.
#
# The build does carry T3 Connect (packages/t3code/default.nix), so a client can
# instead sign in to Ping's Clerk and reach this host over their cloud relay —
# that's a per-client choice made in the UI, and nothing here dials the relay on
# its own.
{ ... }: {
  flake.nixosModules."services.t3code" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.services.t3code;
    port = config.port-selector.ports.t3code;
    dataDir = "/home/${cfg.user}/.t3";
    # opnix/op emit the SSH key with no trailing newline, and OpenSSH then
    # refuses to load it ("error in libcrypto: unsupported") — so agents can't
    # auth or sign against GitHub. Re-emit the key with exactly one trailing
    # newline into a stable path that git/ssh point at (see hosts/luna/home.nix).
    # Secret and key file keep their paseo-era names — same key, and renaming
    # would churn both the opnix path and the on-disk file for nothing.
    sshKey = "/home/${cfg.user}/.ssh/id_paseo";
    prepare = pkgs.writeShellApplication {
      name = "t3code-prepare";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        install -d -m700 "/home/${cfg.user}/.ssh"
        # `test -s` fails (→ ExecStartPre fails → systemd retries) if opnix
        # hasn't populated the secret yet, e.g. a boot race.
        test -s "${config.services.onepassword-secrets.secretPaths.paseoSshKey}"
        umask 077
        printf '%s\n' "$(cat "${config.services.onepassword-secrets.secretPaths.paseoSshKey}")" > "${sshKey}"
      '';
    };
  in {
    options.myNixOS.services.t3code = {
      enable = lib.mkEnableOption "myNixOS.services.t3code";
      user = lib.mkOption {
        type = lib.types.str;
        default = "cramt";
        description = ''
          Real login user whose `systemd --user` manager runs the server. Its
          home-manager profile (git/ssh, claude/codex CLIs) is what spawned
          agents inherit. Must be one of this host's home-users.
        '';
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = ''
          Interface to bind. Defaults to every interface so LAN clients can
          reach it; `openFirewall` decides whether that is actually reachable.
        '';
      };
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open the server's TCP port. Pairing tokens are the auth boundary.";
      };
      onDiskSshKey.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Render the personal SSH key from opnix to disk for agents to auth and
          sign with. Only for headless hosts: on a host with a desktop session
          the 1Password agent already covers this, and dropping a private key
          on disk there buys nothing.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      # Pinned rather than hash-assigned: clients get bookmarked/typed by hand,
      # so the port has to be the same everywhere and stable across renames.
      # 3773 is upstream's own default. Still goes through port-selector so a
      # future service that wants 3773 collides loudly at eval.
      port-selector.set-ports."3773" = "t3code";

      # Headless host: enable linger so the user's systemd manager (and the
      # server) come up at boot without an interactive login.
      users.users.${cfg.user}.linger = true;

      # The data dir can't be created by the user session: luna bind-mounts it
      # onto /pool (hosts/luna/configuration.nix) and the mount unit makes that
      # source dir root-owned, so the user's ExecStartPre can neither chmod nor
      # write it and the unit crash-loops. Own it from the system side, which
      # runs after local-fs.target and therefore lands on the mounted inode.
      systemd.tmpfiles.settings."10-t3code".${dataDir}.d = {
        user = cfg.user;
        group = config.users.users.${cfg.user}.group;
        mode = "0700";
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ port ];

      # `t3` CLI on the system PATH (stable /run/current-system/sw/bin) so
      # `ssh <user>@host t3 pair` prints the pairing token without depending on
      # the user's shell dotfiles — see `just t3_pair`.
      environment.systemPackages = [ pkgs.t3code ];

      # The server as a per-user systemd unit, defined in the user's
      # home-manager (NixOS→HM bridge from modules/bundles/nixos-users.nix).
      # HM uses INI-style Unit/Service/Install sections, not NixOS
      # serviceConfig/wantedBy.
      home-manager.users.${cfg.user} = { ... }: {
        systemd.user.services.t3code = {
          Unit.Description = "T3 Code - self-hosted server for AI coding agents";
          Install.WantedBy = [ "default.target" ];
          Service = {
            ExecStart = lib.concatStringsSep " " [
              "${pkgs.t3code}/bin/t3 serve"
              "--host ${cfg.host}"
              "--port ${toString port}"
              "--base-dir ${dataDir}"
              "--no-browser"
            ];
            WorkingDirectory = "/home/${cfg.user}";
            Environment = [
              "NODE_ENV=production"
              "T3CODE_HOME=${dataDir}"
              # Explicit PATH so agent processes the server spawns find git/ssh
              # + the claude/codex CLIs. systemd --user does not reliably put
              # the per-user profile on PATH, so set it here.
              "PATH=/home/${cfg.user}/.nix-profile/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin"
            ];
            Restart = "on-failure";
            RestartSec = "5";
            # Agent tool calls run as children of the server and share this
            # cgroup. systemd's default OOMPolicy=stop would let one greedy
            # child take down the server and every other live agent with it.
            OOMPolicy = "continue";
            KillMode = "mixed";
            KillSignal = "SIGTERM";
            TimeoutStopSec = "15";
          } // lib.optionalAttrs cfg.onDiskSshKey.enable {
            ExecStartPre = "${prepare}/bin/t3code-prepare";
          };
        };
      };
    };
  };
}
