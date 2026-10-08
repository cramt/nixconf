# T3 Code server — self-hosted orchestrator that runs coding agents on this
# host, so agent work can be offloaded from a laptop to a server. Replaces the
# paseo daemon that used to hold this slot.
#
# Runs as a real login user's `systemd --user` service (not a system unit), so
# the server lives in a genuine user session and the agents it spawns inherit
# that user's home-manager environment: git, ssh keys, and the agent CLIs
# (claude). Upstream's own `t3 service install` writes a user
# unit too, but it also installs a self-updating launcher under ~/.t3 — Nix owns
# the version here, so the unit is hand-rolled around `t3 serve` instead.
#
# Two ways in, both ending at t3code's own one-time pairing token (`just
# t3_pair`), which upstream has no switch to turn off:
#   - LAN: the server binds every interface and the port is opened, for the
#     desktop app, which can't get through a browser login portal.
#   - `subdomain`: a caddy vhost behind the authelia passkey portal, for a
#     browser anywhere. No pairing there: see proxyAuth below.
#
# We used to compile T3 Connect (Ping's Clerk login + cloud relay) in for the
# off-LAN case. Its relay client downloaded its own cloudflared into
# ~/.t3/tools/, outside Nix, which is why the caddy route replaced it.
#
# proxyAuth borrows upstream's reusable dev token (apps/server/src/auth/
# ReusableDevAuth.ts) as a fixed session secret. Its matching cookie,
# `t3_dev_session_<sha256 of token>`, authenticates any request that carries
# no other credential, so caddy adds it after authelia lets a request through
# and the browser never sees the pairing screen. The token only switches on
# alongside --dev-url, and that flag's other effects are why the URL points
# at a dead port: requests whose Host is loopback get redirected there (caddy
# forwards the public Host, so only `curl localhost` on the box hits it), and
# Codex's ChatGPT login returns there instead of to /welcome. No upstream
# issue for a real trusted-proxy mode yet; drop this when one lands.
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
    #
    # No "pi": upstream has no Pi driver (every community PR adding one,
    # e.g. pingdotgg/t3code#7211, was closed unmerged). We briefly ran that
    # fork, but its orchestrator-v2 broke the hosted client at app.t3.codes,
    # which is built from main. The fork also reused migration ids 044-052 for
    # different migrations, so a state.sqlite it touched crash-loops upstream
    # ("no such column: auto_pull") until
    # `DELETE FROM effect_sql_migrations WHERE migration_id >= 44` lets
    # upstream's guarded 044+ replay (done on mars 2026-10-02).
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
    proxyAuthDir = "/var/lib/t3code-proxy-auth";
    proxyAuthToken = "${proxyAuthDir}/token";
    proxyAuthCookie = "${proxyAuthDir}/cookie";
    serveArgs = [
      "--host ${cfg.host}"
      "--port ${toString port}"
      "--base-dir ${dataDir}"
      "--no-browser"
    ] ++ lib.optional cfg.proxyAuth "--dev-url http://127.0.0.1:9";
    # The token goes in through the environment, read here rather than via
    # EnvironmentFile so a not-yet-generated file is an ordinary failed start
    # that Restart= retries.
    serve = pkgs.writeShellScript "t3code-serve" (
      lib.optionalString cfg.proxyAuth ''
        test -s ${proxyAuthToken}
        T3CODE_DEV_AUTH_TOKEN=$(< ${proxyAuthToken})
        export T3CODE_DEV_AUTH_TOKEN
      ''
      + "exec ${pkgs.t3code}/bin/t3 serve ${lib.concatStringsSep " " serveArgs}\n"
    );
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
          home-manager profile (git/ssh, the claude CLI) is what
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
      subdomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "t3";
        description = ''
          Expose the server as this caddy vhost, behind the authelia passkey
          portal. Needs caddy and authelia on this host.
        '';
      };
      proxyAuth = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Skip pairing on the `subdomain` vhost: caddy presents a fixed session
          to t3code once authelia has passed the request. LAN clients still
          pair as usual.
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
        example = {codex = false;};
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
          assertion = cfg.proxyAuth -> cfg.subdomain != null;
          message = "myNixOS.services.t3code.proxyAuth needs a subdomain to proxy through.";
        }
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

      myNixOS.services.caddy.serviceMap = lib.mkIf (cfg.subdomain != null) {
        ${cfg.subdomain} = {
          inherit port;
          forward-auth = true;
          reverse-proxy-config = lib.optionalString cfg.proxyAuth ''
            header_up Cookie "{file.${proxyAuthCookie}}; {http.request.header.Cookie}"
          '';
        };
      };

      systemd.tmpfiles.settings."10-t3code-proxy-auth" = lib.mkIf cfg.proxyAuth {
        ${proxyAuthDir}.d = {
          user = cfg.user;
          group = config.services.caddy.group;
          mode = "0750";
        };
      };

      systemd.services.t3code-proxy-auth = lib.mkIf cfg.proxyAuth {
        description = "Generate the session secret caddy presents to t3code";
        wantedBy = ["multi-user.target"];
        after = ["systemd-tmpfiles-setup.service"];
        serviceConfig.Type = "oneshot";
        path = [pkgs.openssl pkgs.coreutils];
        script = ''
          umask 027
          if [ ! -s ${proxyAuthToken} ]; then
            openssl rand -hex 32 > ${proxyAuthToken}.new
            mv ${proxyAuthToken}.new ${proxyAuthToken}
          fi
          token=$(< ${proxyAuthToken})
          # Upstream names the cookie after the token's sha256 (ReusableDevAuth.ts).
          hash=$(printf %s "$token" | sha256sum | cut -d" " -f1)
          printf 't3_dev_session_%s=%s' "$hash" "$token" > ${proxyAuthCookie}
          chown ${cfg.user}:${config.services.caddy.group} ${proxyAuthToken} ${proxyAuthCookie}
          chmod 0640 ${proxyAuthToken} ${proxyAuthCookie}
        '';
      };

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
            ExecStart = "${serve}";
            WorkingDirectory = "/home/${cfg.user}";
            Environment = [
              "NODE_ENV=production"
              "T3CODE_HOME=${dataDir}"
              # Explicit PATH so agent processes the server spawns find git/ssh
              # + the claude CLI. systemd --user does not reliably put
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
