# T3 Code server — self-hosted orchestrator that runs coding agents on this
# host, so agent work can be offloaded from a laptop to a server.
#
# Runs as a real login user's `systemd --user` service (not a system unit), so
# the server lives in a genuine user session and the agents it spawns inherit
# that user's home-manager environment: git, ssh keys, and the agent CLIs
# (claude). Upstream's own `t3 service install` writes a user
# unit too, but it also installs a self-updating launcher under ~/.t3 — Nix owns
# the version here, so the unit is hand-rolled around `t3 serve` instead.
#
# Every client (desktop app, Android app, browser) pairs the stock way, over
# the LAN port or the `subdomain` vhost. With `sharedSecret` set, the pairing
# code is a fixed secret from 1Password instead of `just t3_pair`'s one-time
# token, and it works any number of times, so a browser can bookmark
# `https://<subdomain>/pair#token=<secret>`. The vhost then skips authelia,
# because the apps can't get through a browser login portal: t3code's own auth
# is the boundary.
#
# The secret rides on upstream's reusable dev token (T3CODE_DEV_AUTH_TOKEN,
# apps/server/src/auth/ReusableDevAuth.ts), which the server also accepts as a
# pairing credential. Upstream only honours it in dev mode (--dev-url), whose
# redirects broke the desktop app's SSH reuse and Codex's ChatGPT login, so our
# build ungates it (overlays/default.nix).
#
# We used to compile T3 Connect (Ping's Clerk login + cloud relay) in for the
# off-LAN case. Its relay client downloaded its own cloudflared into
# ~/.t3/tools/, outside Nix, which is why the caddy route replaced it.
{ ... }: {
  flake.nixosModules."services.t3code" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.services.t3code;
    port = config.port-selector.ports.t3code;
    dataDir = "/home/${cfg.user}/.t3";
    # opnix/op emit the SSH key with no trailing newline, and OpenSSH then
    # refuses to load it ("error in libcrypto: unsupported") — so agents can't
    # auth or sign against GitHub. Re-emit the key with exactly one trailing
    # newline into a stable path that git/ssh point at (the home-manager block
    # under onDiskSshKey below).
    sshKey = "/home/${cfg.user}/.ssh/id_personal";
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
    #
    # customModels only goes in the envelope's `config`: upstream migrates the
    # `providers` mirror once and then drops it (apps/server/src/
    # serverSettings.ts, migrateLegacyProviderSettings), so anything beyond
    # `enabled` written there is never read.
    declaredDrivers = lib.unique (lib.attrNames cfg.providers ++ lib.attrNames cfg.customModels);
    hasDeclaredSettings = declaredDrivers != [] || cfg.usageHub != null;
    declaredSettings = (pkgs.formats.json {}).generate "t3code-declared-settings.json" {
      providers = lib.mapAttrs (_: enabled: {inherit enabled;}) cfg.providers;
      providerInstances = lib.genAttrs declaredDrivers (driver:
        {inherit driver;}
        // lib.optionalAttrs (cfg.providers ? ${driver}) {enabled = cfg.providers.${driver};}
        // lib.optionalAttrs (cfg.customModels ? ${driver}) {
          config.customModels = map (m: lib.filterAttrs (_: v: v != null) m) cfg.customModels.${driver};
        });
    };
    usageHubSettings = (pkgs.formats.json {}).generate "t3code-usage-hub.json" {
      kind = "cliproxy";
      inherit (cfg.usageHub) label url;
      enabled = true;
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
      '' + lib.optionalString (cfg.usageHub != null) ''
        # The key is read here rather than baked into declaredSettings so it
        # never lands in the store. `test -s` turns a not-yet-generated key
        # into a failed start that Restart= retries.
        test -s ${lib.escapeShellArg cfg.usageHub.managementKeyFile}
        jq --slurpfile hub ${usageHubSettings} \
          --rawfile key ${lib.escapeShellArg cfg.usageHub.managementKeyFile} \
          '.usageLimitSources.cliproxy = $hub[0] + {managementKey: ($key | rtrimstr("\n"))}' \
          "${settingsFile}.new" > "${settingsFile}.hub"
        mv "${settingsFile}.hub" "${settingsFile}.new"
      '' + ''
        mv "${settingsFile}.new" "${settingsFile}"
      '';
    };
    serveArgs = [
      "--host ${cfg.host}"
      "--port ${toString port}"
      "--base-dir ${dataDir}"
      "--no-browser"
    ];
    sharedSecretPath = config.services.onepassword-secrets.secretPaths.t3codeSharedSecret;
    # The secret goes in through the environment, read here rather than via
    # EnvironmentFile so a not-yet-rendered opnix file is an ordinary failed
    # start that Restart= retries.
    serve = pkgs.writeShellScript "t3code-serve" (
      lib.optionalString (cfg.sharedSecret != null) ''
        test -s ${sharedSecretPath}
        T3CODE_DEV_AUTH_TOKEN=$(< ${sharedSecretPath})
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
        test -s "${config.services.onepassword-secrets.secretPaths.personalSshKey}"
        umask 077
        printf '%s\n' "$(cat "${config.services.onepassword-secrets.secretPaths.personalSshKey}")" > "${sshKey}"
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
          Expose the server as this caddy vhost: behind the authelia passkey
          portal, or with `sharedSecret`, behind t3code's own pairing alone.
        '';
      };
      sharedSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "op://Homelab/T3Code/password";
        description = ''
          1Password reference to a fixed pairing secret, at least 32
          characters (upstream refuses to start on a shorter one). Every client
          pairs with it, and the `subdomain` vhost drops authelia so the apps
          can reach it. After rotating it, restart the user unit:
          `systemctl --user -M <user>@ restart t3code`.
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
      customModels = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf (lib.types.submodule {
          options = {
            slug = lib.mkOption {
              type = lib.types.str;
              description = "Model id handed to the agent CLI (claude --model).";
            };
            name = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Label in the model picker; the slug when unset.";
            };
          };
        }));
        default = {};
        example = {claudeAgent = [{slug = "m365/gpt-5.5"; name = "GPT-5.5 (M365)";}];};
        description = ''
          Extra models in a driver's picker, keyed by driver kind. Replaces
          that driver's custom model list on every start, so models added in
          the UI for a driver named here don't survive a restart.
        '';
      };
      usageHub = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              example = "http://127.0.0.1:8317";
              description = "CLIProxyAPI base URL; t3code appends /v0/management itself.";
            };
            managementKeyFile = lib.mkOption {
              type = lib.types.str;
              description = ''
                File holding the management key, readable by `user`. Read at
                start, never copied into the store; the server then moves it
                out of settings.json into its own secret store.
              '';
            };
            label = lib.mkOption {
              type = lib.types.str;
              default = "CLIProxyAPI";
              description = "Name shown under Usage → Limits.";
            };
          };
        });
        default = null;
        description = ''
          CLIProxyAPI hub whose pooled account limits show under Usage →
          Limits. Usage only: agent requests reach the pool through each
          CLI's own config (claude's wrapper), not through this. Rewritten on
          every start, so the hub can't be edited or removed in the UI.
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
      selfDeploy.enable = lib.mkEnableOption ''
        letting agents `just deploy` this host: ssh to its own name offers the
        on-disk key, which root already accepts (it's one of myLib/keys.nix's)
      '';
    };

    config = lib.mkIf cfg.enable {
      # No `services` restart wiring: opnix restarts *system* units, but t3code
      # is a user unit -- a dangling `services = ["t3code"]` would make opnix
      # emit a stub system unit with no ExecStart and break activation. After
      # rotating the key, restart the user service by hand:
      #   systemctl --user -M cramt@ restart t3code
      # The 1Password item is still named after paseo, which first needed the
      # key on disk; it holds the Personal key (the one in myLib/keys.nix).
      services.onepassword-secrets.secrets.personalSshKey = lib.mkIf cfg.onDiskSshKey.enable {
        reference = "op://Homelab/Paseo/sshPrivateKey";
        owner = "cramt";
        mode = "0600";
      };
      assertions = [
        {
          assertion = cfg.selfDeploy.enable -> cfg.onDiskSshKey.enable;
          message = "myNixOS.services.t3code.selfDeploy needs onDiskSshKey: that's the key it logs in to root with.";
        }
        {
          assertion = lib.all (d: lib.elem d knownDrivers) declaredDrivers;
          message = ''
            myNixOS.services.t3code.{providers,customModels} have unknown driver kinds: ${
              lib.concatStringsSep ", " (lib.subtractLists knownDrivers declaredDrivers)
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
          forward-auth = cfg.sharedSecret == null;
        };
      };

      # owner, not a `services` restart: opnix only restarts system units and
      # this is a user unit (see the personalSshKey note above).
      services.onepassword-secrets.secrets.t3codeSharedSecret = lib.mkIf (cfg.sharedSecret != null) {
        reference = cfg.sharedSecret;
        owner = cfg.user;
        mode = "0400";
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
        # No 1Password agent or op-ssh-sign on a headless host, so GitHub auth
        # and commit signing both go through the on-disk key, letting agents
        # clone, commit and push.
        myHomeManager = lib.mkIf cfg.onDiskSshKey.enable {
          ssh.use1Password = false;
          gpg-agent.enableSshSupport = false;
        };
        programs.ssh.settings."github.com" = lib.mkIf cfg.onDiskSshKey.enable {
          IdentityFile = sshKey;
          IdentitiesOnly = true;
          StrictHostKeyChecking = "accept-new";
        };
        # deploy-rs and `just deploy`'s probe both reach the host by its bare
        # name (the default `address` in modules/flake/hosts.nix).
        programs.ssh.settings.${config.networking.hostName} = lib.mkIf cfg.selfDeploy.enable {
          IdentityFile = sshKey;
          IdentitiesOnly = true;
        };
        programs.git.settings.user.signingKey = lib.mkIf cfg.onDiskSshKey.enable (lib.mkForce sshKey);

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
              ++ lib.optional hasDeclaredSettings "${seedSettings}/bin/t3code-seed-settings";
          };
        };
      };
    };
  };
}
