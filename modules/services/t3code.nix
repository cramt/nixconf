# T3 Code server, fleet side. The service itself is my-nixpkgs'
# nixosModules.t3code (`services.t3code`): the user unit, settings.json merge,
# managed policy, Device panel tools, and declared projects and scheduled
# tasks. Hosts set those directly. This file only adds what's ours:
#  - the port through port-selector, and the caddy vhost
#  - secrets from op-secrets: the shared pairing secret and the on-disk SSH key
#  - home-manager ssh/git config for headless hosts' agents
#  - the CLIProxyAPI usage hub (fed by cli-proxy-api.nix) and OTLP metrics
#
# With `sharedSecret` set, the pairing code is a fixed secret from 1Password
# instead of `just t3_pair`'s one-time token, and it works any number of times,
# so a browser can bookmark `https://<subdomain>/pair#token=<secret>`. The
# vhost then skips authelia, because the apps can't get through a browser
# login portal: t3code's own auth is the boundary.
#
# We used to compile T3 Connect (Ping's Clerk login + cloud relay) in for the
# off-LAN case. Its relay client downloaded its own cloudflared into
# ~/.t3/tools/, outside Nix, which is why the caddy route replaced it.
#
# No Pi driver: upstream has none (every community PR adding one, e.g.
# pingdotgg/t3code#7211, was closed unmerged). We briefly ran that fork, but
# its orchestrator-v2 broke the hosted client at app.t3.codes, which is built
# from main. The fork also reused migration ids 044-052 for different
# migrations, so a state.sqlite it touched crash-loops upstream ("no such
# column: auto_pull") until `DELETE FROM effect_sql_migrations WHERE
# migration_id >= 44` lets upstream's guarded 044+ replay (done on mars
# 2026-10-02).
{inputs, ...}: {
  flake.nixosModules."services.t3code" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.t3code;
    port = config.port-selector.ports.t3code;
    inherit (config.myNixOS.services.metrics) otlpMetricsUrl;
    # op emits the SSH key with no trailing newline, and OpenSSH then
    # refuses to load it ("error in libcrypto: unsupported"), so agents can't
    # auth or sign against GitHub. Re-emit the key with exactly one trailing
    # newline into a stable path that git/ssh point at.
    sshKey = "/home/${cfg.user}/.ssh/id_personal";
    # Gated on every secret t3code reads (myNixOS.secrets.userServices), and
    # the units that only make sense with it up: declare would otherwise run
    # against a server that isn't there and retry forever.
    secretGated =
      ["t3code" "t3code-declare"]
      ++ lib.optional (config.services.t3code.linkedEnvironments.peers != {}) "t3code-link-peers";
    prepareSshKey = pkgs.writeShellApplication {
      name = "t3code-prepare-ssh-key";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        install -d -m700 "/home/${cfg.user}/.ssh"
        umask 077
        printf '%s\n' "$(cat "${config.myNixOS.secrets.personalSshKey.path}")" > "${sshKey}"
      '';
    };
  in {
    imports = [inputs.my-nixpkgs.nixosModules.t3code];

    options.myNixOS.services.t3code = {
      enable = lib.mkEnableOption "myNixOS.services.t3code";
      user = lib.mkOption {
        type = lib.types.str;
        default = "cramt";
        description = "Login user that runs the server. Must be one of this host's home-users.";
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
        # The fleet's links pair with it (t3code-fleet.nix).
        default = (import ../../myLib/t3code-fleet.nix).sharedSecret;
        example = "op://Homelab/T3Code/password";
        description = ''
          1Password reference to a fixed pairing secret, at least 32
          characters (upstream refuses to start on a shorter one). Every client
          pairs with it, and the `subdomain` vhost drops authelia so the apps
          can reach it. After rotating it, restart the user unit:
          `systemctl --user -M <user>@ restart t3code`.
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
              description = "File holding the management key, readable by `user`.";
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
          CLI's own config (claude's wrapper), not through this.
        '';
      };
      onDiskSshKey.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Render the personal SSH key from 1Password to disk for agents to auth and
          sign with. Only for headless hosts: with a desktop session the
          1Password agent already covers this.
        '';
      };
      selfDeploy.enable = lib.mkEnableOption ''
        letting agents `just deploy` this host: ssh to its own name offers the
        on-disk key, which root already accepts (it's one of myLib/keys.nix's)
      '';
    };

    config = lib.mkMerge [
      {
        # Whether or not this host runs a server: the desktop app reads the
        # policy too (t3code-remotes turns it on there).
        services.t3code.policy = {
          organization = "nixconf";
          limits.telemetry = lib.mkDefault false;
        };
        # Beta. Locked on in the policy, so the desktop app gets it as well.
        services.t3code.linkedEnvironments.enable = true;
      }

      (lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.selfDeploy.enable -> cfg.onDiskSshKey.enable;
            message = "myNixOS.services.t3code.selfDeploy needs onDiskSshKey: that's the key it logs in to root with.";
          }
        ];

        services.t3code = {
          enable = true;
          inherit (cfg) user;
          inherit port;
          openFirewall = true;
          sharedSecretFile = lib.mkIf (cfg.sharedSecret != null) config.myNixOS.secrets.t3codeSharedSecret.path;
          preStart = lib.optional cfg.onDiskSshKey.enable (lib.getExe prepareSshKey);
          # Threads that were mid-turn when the server stopped (deploy, crash,
          # reboot) resume with a "continue where you left off" prompt.
          settings = lib.mkMerge [
            {continueThreadsAfterServerUpdate = true;}
            (lib.mkIf (cfg.usageHub != null) {
              usageLimitSources.cliproxy = {
                kind = "cliproxy";
                inherit (cfg.usageHub) label url;
                enabled = true;
              };
            })
          ];
          secretSettings = lib.mkIf (cfg.usageHub != null) {
            "usageLimitSources.cliproxy.managementKey" = cfg.usageHub.managementKeyFile;
          };
          # Metrics only: there's no trace or log backend in the fleet. Without
          # a pinned service.instance.id upstream mints a random UUID per
          # process, so every restart would start a fresh set of series.
          environment = lib.mkIf (otlpMetricsUrl != null) {
            T3CODE_OTLP_METRICS_URL = otlpMetricsUrl;
            T3CODE_OTLP_PROTOCOL = "http/protobuf";
            OTEL_RESOURCE_ATTRIBUTES = "service.instance.id=${config.networking.hostName}";
          };
        };

        # Pinned rather than hash-assigned: clients get bookmarked/typed by
        # hand, so the port has to be the same everywhere and stable across
        # renames. 3773 is upstream's own default. Still goes through
        # port-selector so a future service that wants 3773 collides loudly.
        port-selector.set-ports."3773" = "t3code";

        myNixOS.services.caddy.serviceMap = lib.mkIf (cfg.subdomain != null) {
          ${cfg.subdomain} = {
            inherit port;
            forward-auth = cfg.sharedSecret == null;
          };
        };

        # userServices only gates the start; after rotating either secret,
        # restart the user service by hand:
        #   systemctl --user -M cramt@ restart t3code
        myNixOS.secrets = {
          t3codeSharedSecret = lib.mkIf (cfg.sharedSecret != null) {
            reference = cfg.sharedSecret;
            owner = cfg.user;
            mode = "0400";
            userServices = secretGated;
          };
          # The 1Password item is still named after paseo, which first needed
          # the key on disk; it holds the Personal key (the one in myLib/keys.nix).
          personalSshKey = lib.mkIf cfg.onDiskSshKey.enable {
            reference = "op://Homelab/Paseo/sshPrivateKey";
            owner = "cramt";
            mode = "0600";
            userServices = secretGated;
          };
        };

        home-manager.users.${cfg.user} = {...}: {
          # No 1Password agent or op-ssh-sign on a headless host, so GitHub
          # auth and commit signing both go through the on-disk key, letting
          # agents clone, commit and push.
          myHomeManager = lib.mkIf cfg.onDiskSshKey.enable {
            ssh.use1Password = false;
            gpg-agent.enableSshSupport = false;
          };
          programs.ssh.settings."github.com" = lib.mkIf cfg.onDiskSshKey.enable {
            IdentityFile = sshKey;
            IdentitiesOnly = true;
            StrictHostKeyChecking = "accept-new";
          };
          # deploy-rs and `just deploy`'s probe both reach the host by its
          # bare name (the default `address` in modules/flake/hosts.nix).
          programs.ssh.settings.${config.networking.hostName} = lib.mkIf cfg.selfDeploy.enable {
            IdentityFile = sshKey;
            IdentitiesOnly = true;
          };
          programs.git.settings.user.signingKey = lib.mkIf cfg.onDiskSshKey.enable (lib.mkForce sshKey);
        };
      })
    ];
  };
}
