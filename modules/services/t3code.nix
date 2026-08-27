# T3 Code server — self-hosted orchestrator that runs coding agents on this
# host, so agent work can be offloaded from a laptop to a server. Replaces the
# paseo daemon that used to hold this slot.
#
# Runs as a real login user's `systemd --user` service (not a system unit), so
# the server lives in a genuine user session and the agents it spawns inherit
# that user's home-manager environment: git, ssh keys, and the agent CLIs
# (claude, codex, opencode). Upstream's own `t3 service install` writes a user
# unit too, but it also installs a self-updating launcher under ~/.t3 — Nix owns
# the version here, so the unit is hand-rolled around `t3 serve` instead.
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
#
# Once linked, though, the relay side is not declarative. The relay client
# downloads its own cloudflared (~39MB, straight from GitHub releases) into
# ~/.t3/tools/cloudflared/<version>/, so that binary's version is upstream's
# choice rather than anything pinned here, and it re-downloads whenever they bump
# it. The server bundle does read T3CODE_CLOUDFLARED_PATH, so pointing that at
# pkgs.cloudflared should hand the job back to Nix — untested. In the same vein
# `t3 connect` offers to "update or repair" the installed service, which means
# dropping upstream's self-updating launcher in ~/.t3 alongside the Nix-owned
# unit; always decline it. Worth a proper pass at some point to work out how much
# of ~/.t3 can be owned declaratively and how much is genuinely mutable state.
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
    # `--base-dir` plus no dev server puts the server's mutable state here
    # (apps/server/src/config.ts, deriveServerPaths).
    stateDir = "${dataDir}/userdata";
    settingsFile = "${stateDir}/settings.json";
    # Every driver t3code ships. Guards against a typo'd key silently landing
    # in settings.json as a phantom provider — unknown driver envelopes are
    # preserved verbatim by design, so nothing upstream would complain.
    knownDrivers = ["codex" "claudeAgent" "cursor" "grok" "opencode"];
    # Both shapes, because both are live upstream: `providers.<kind>` is the
    # legacy mirror the settings UI reads, and `providerInstances.<kind>` is
    # the envelope the registry actually resolves — an explicit envelope wins
    # over the mirror, so writing only one of them would leave the UI and the
    # running server disagreeing. The instance id is the driver kind itself.
    declaredSettings = (pkgs.formats.json {}).generate "t3code-declared-settings.json" {
      providers = lib.mapAttrs (_: enabled: {inherit enabled;}) cfg.providers;
      providerInstances = lib.mapAttrs (driver: enabled: {inherit driver enabled;}) cfg.providers;
    };
    seedSettings = pkgs.writeShellApplication {
      name = "t3code-seed-settings";
      runtimeInputs = [pkgs.coreutils pkgs.jq];
      text = ''
        install -d -m700 "${stateDir}"
        # The UI owns everything else in this file, so merge rather than
        # overwrite. A file the server itself would reject is worth nothing —
        # it falls back to defaults and ignores the contents — so a parse
        # failure starts from scratch instead of failing the unit.
        if ! current=$(jq . "${settingsFile}" 2>/dev/null); then
          current='{}'
        fi
        printf '%s' "$current" \
          | jq --slurpfile declared ${declaredSettings} '. * $declared[0]' \
          > "${settingsFile}.new"
        mv "${settingsFile}.new" "${settingsFile}"
      '';
    };
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
          home-manager profile (git/ssh, the claude/codex/opencode CLIs) is what
          spawned agents inherit. Must be one of this host's home-users.
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
      providers = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        default = {};
        example = {opencode = true;};
        description = ''
          Coding-agent providers to pin on (or off) in the server's
          settings.json, keyed by t3code driver kind. codex and claudeAgent
          ship enabled; cursor, grok and opencode ship disabled and are
          otherwise only reachable through the settings UI.

          Merged into settings.json on every start, so a toggle made in the UI
          for a provider named here is undone on the next restart. Providers
          left out are untouched and stay UI-owned.
        '';
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
      assertions = [
        {
          assertion = lib.all (d: lib.elem d knownDrivers) (lib.attrNames cfg.providers);
          message = ''
            myNixOS.services.t3code.providers has unknown driver kinds: ${
              lib.concatStringsSep ", " (lib.subtractLists knownDrivers (lib.attrNames cfg.providers))
            }. Known kinds: ${lib.concatStringsSep ", " knownDrivers}.
          '';
        }
      ];

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
            ExecStartPre =
              lib.optional cfg.onDiskSshKey.enable "${prepare}/bin/t3code-prepare"
              ++ lib.optional (cfg.providers != {}) "${seedSettings}/bin/t3code-seed-settings";
          };
        };
      };
    };
  };
}
