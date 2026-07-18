# Paseo daemon — self-hosted orchestrator that runs coding agents on this host,
# so you can offload agent work from a laptop to a server.
#
# Runs as a real login user's `systemd --user` service (not a system unit), so
# the daemon lives in a genuine user session and the agents it spawns inherit
# that user's home-manager environment: git, ssh keys, and the agent CLIs
# (claude, codex). Upstream's nixosModule only ships a *system* service, so we
# hand-roll the user unit from `inputs.paseo.packages`.
#
# Connectivity is paseo's own relay ("quick connect"): the daemon dials out to
# relay.paseo.sh and you pair a client with the link from `paseo daemon pair`
# (see `just paseo_pair`). No reverse proxy, DNS, TLS, or daemon password — the
# one-shot pairing link *is* the capability. Binds loopback only; the relay
# carries all remote traffic, so nothing is exposed on the LAN.
{ inputs, ... }: {
  flake.nixosModules."services.paseo" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.services.paseo;
    paseoPkg = inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.default;
    dataDir = "/home/${cfg.user}/.paseo";
    # opnix/op emit the SSH key with no trailing newline, and OpenSSH then
    # refuses to load it ("error in libcrypto: unsupported") — so agents can't
    # auth or sign against GitHub. Re-emit the key with exactly one trailing
    # newline into a stable path that git/ssh point at (see hosts/luna/home.nix).
    sshKeyRaw = config.services.onepassword-secrets.secretPaths.paseoSshKey;
    sshKey = "/home/${cfg.user}/.ssh/id_paseo";
    normalizeSshKey = pkgs.writeShellApplication {
      name = "paseo-normalize-ssh-key";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        install -d -m700 "${dataDir}" "/home/${cfg.user}/.ssh"
        # `test -s` fails (→ ExecStartPre fails → systemd retries) if opnix
        # hasn't populated the secret yet, e.g. a boot race.
        test -s "${sshKeyRaw}"
        umask 077
        printf '%s\n' "$(cat "${sshKeyRaw}")" > "${sshKey}"
      '';
    };
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
    };

    config = lib.mkIf cfg.enable {
      # Headless host: enable linger so the user's systemd manager (and the
      # daemon) come up at boot without an interactive login.
      users.users.${cfg.user}.linger = true;

      # `paseo` CLI on the system PATH (stable /run/current-system/sw/bin) so
      # `ssh <user>@host paseo daemon pair` prints the quick-connect link
      # without depending on the user's shell dotfiles — see `just paseo_pair`.
      environment.systemPackages = [ paseoPkg ];

      # The daemon as a per-user systemd unit, defined in the user's
      # home-manager (NixOS→HM bridge from modules/bundles/nixos-users.nix).
      # HM uses INI-style Unit/Service/Install sections, not NixOS
      # serviceConfig/wantedBy.
      home-manager.users.${cfg.user} = { ... }: {
        systemd.user.services.paseo = {
          Unit.Description = "Paseo - self-hosted daemon for AI coding agents";
          Install.WantedBy = [ "default.target" ];
          Service = {
            ExecStartPre = "${normalizeSshKey}/bin/paseo-normalize-ssh-key";
            # Relay left on (upstream default) so quick-connect pairing works.
            ExecStart = "${paseoPkg}/bin/paseo-server";
            Environment = [
              "NODE_ENV=production"
              "PASEO_HOME=${dataDir}"
              # Loopback-only bind; the relay handles remote access. NOT paseo's
              # default 6767 — nixarr's bazarr already owns 6767 on this host, so
              # the daemon would fail to bind (EADDRINUSE) and `paseo daemon
              # pair` would silently fall back to a dead offer. The `paseo` CLI
              # auto-discovers this port from ~/.paseo/paseo.pid, so pairing
              # needs no --host flag.
              "PASEO_LISTEN=127.0.0.1:6776"
              # Explicit PATH so agent processes the daemon spawns find git/ssh
              # + the claude/codex CLIs. systemd --user does not reliably put
              # the per-user profile on PATH, so set it here.
              "PATH=/home/${cfg.user}/.nix-profile/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin"
            ];
            Restart = "on-failure";
            RestartSec = "5";
            # Graceful shutdown (server handles SIGTERM with a 10s timeout)
            KillSignal = "SIGTERM";
            TimeoutStopSec = "15";
          };
        };
      };
    };
  };
}
