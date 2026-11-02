# T3 Code's managed policy (upstream docs/user/managed-policy.md): a
# machine-wide /etc/t3code/policy.json that every T3 Code server on the host
# reads at start, the background service and the desktop app's own alike. Each
# `settings` entry is a dot path into the server's settings.json, either a
# default the UI can still change (`locked = false`) or a value it can't
# (`locked = true`, shown as "Managed by <organization>"). Policy values are
# never written into settings.json, so dropping an entry gives the user's own
# choice back.
#
# This is the declarative half of t3code config. The other half is still the
# settings.json merge in t3code.nix, for the two things a policy can't hold:
# secrets (the file is world-readable) and entries the UI must be able to keep
# (a policy *default* can't add a list entry or provider instance).
#
# Upstream refuses to start on a policy it can't fully enforce (unknown key,
# wrong type), so the file is run through this build's own `t3 policy check`:
# a bad policy fails the build instead of crash-looping the server.
#
# Also here because it is machine-wide too: the Device panel's npm tools,
# linked from the store into every T3 Code home on the host.
{ ... }: {
  flake.nixosModules."services.t3code-policy" = { config, lib, pkgs, ... }:
  let
    server = config.myNixOS.services.t3code;
    remotes = config.myNixOS.t3code-remotes;
    cfg = server.policy;
    devices = server.devices;
    json = pkgs.formats.json {};

    document = {
      schemaVersion = 1;
      inherit (cfg) organization settings;
    } // lib.optionalAttrs (cfg.limits != {}) { inherit (cfg) limits; };

    policyFile = pkgs.runCommand "t3code-policy.json" {
      raw = json.generate "t3code-policy-unchecked.json" document;
      nativeBuildInputs = [ pkgs.t3code ];
    } ''
      export HOME=$TMPDIR
      t3 policy check "$raw"
      cp "$raw" $out
    '';

    lock = value: { inherit value; locked = true; };
    tools = pkgs.t3code-device-tools;
  in {
    options.myNixOS.services.t3code = {
      policy = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = server.enable || remotes.enable;
          defaultText = lib.literalExpression "services.t3code.enable || t3code-remotes.enable";
          description = "Write /etc/t3code/policy.json for every T3 Code server on this host.";
        };
        organization = lib.mkOption {
          type = lib.types.str;
          default = "nixconf";
          description = ''Shown as "Managed by <organization>" beside each locked control.'';
        };
        settings = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              value = lib.mkOption {
                type = json.type;
                description = "The setting's value, as it would appear in settings.json.";
              };
              locked = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Pin the value. false only replaces the built-in default.";
              };
            };
          });
          default = {};
          example = { defaultRuntimeMode = { value = "auto-accept-edits"; locked = false; }; };
          description = "Defaults and locks, keyed by dot path into the server's settings.json.";
        };
        limits = lib.mkOption {
          type = json.type;
          default = {};
          example = { maxRuntimeMode = "auto"; webhookTasks = false; };
          description = ''
            The policy's `limits`: maxRuntimeMode, clients, connect, webhookTasks,
            telemetry, browserCookieImport, providers, updates. Upstream's
            ManagedPolicyLimits schema; `t3 policy check` vets it at build.
          '';
        };
        homes = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule {
            options = {
              path = lib.mkOption { type = lib.types.str; };
              user = lib.mkOption { type = lib.types.str; };
            };
          });
          internal = true;
          default = [];
          description = "Every T3CODE_HOME on this host, contributed by the modules that run a server there.";
        };
      };

      devices = {
        enable = lib.mkEnableOption ''
          the Device panel (simulators and emulators). Its two npm tools come
          from the store instead of t3code's own `npm install` into ~/.t3/tools.
          On Linux the local source is Android emulators only, found through
          ANDROID_HOME; remote sources (SSH hosts, EAS, Simlock) work without one
        '';
        agentAccess = lib.mkOption {
          type = lib.types.bool;
          default = devices.enable;
          defaultText = lib.literalExpression "devices.enable";
          description = "Let new agent sessions open and drive the devices (enableAgentDeviceAccess).";
        };
        simlock = {
          enable = lib.mkEnableOption ''
            Simlock device hosts (Labs, alpha): devices leased from your own
            Simlock gateway, https://incubator.callstack.com/simlock. t3code
            never installs Simlock itself
          '';
          secretName = lib.mkOption {
            type = lib.types.functionTo lib.types.str;
            internal = true;
            readOnly = true;
            # opnix only takes camelCase keys.
            default = name: "t3codeSimlock${lib.toUpper (lib.substring 0 1 name)}${lib.substring 1 (-1) name}";
          };
          hosts = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
              options = {
                label = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                };
                gatewayUrl = lib.mkOption {
                  type = lib.types.strMatching "https?://[^[:space:]/]+/?";
                  example = "https://gateway.example.ts.net:4700";
                  description = "The gateway's origin.";
                };
                agentToken = lib.mkOption {
                  type = lib.types.str;
                  example = "op://Homelab/Simlock/credential";
                  description = "1Password reference to the gateway's agent token.";
                };
                maxLeases = lib.mkOption {
                  type = lib.types.ints.between 1 20;
                  default = 2;
                };
                maxLeaseMinutes = lib.mkOption {
                  type = lib.types.ints.between 5 240;
                  default = 60;
                };
              };
            }));
            default = {};
            description = ''
              Gateways the background server leases from. Rewritten into
              settings.json on every start (the token can't live in the
              world-readable policy), so hosts added in the UI are dropped
              while any are declared here.
            '';
          };
        };
      };
    };

    config = lib.mkMerge [
      {
        myNixOS.services.t3code.policy = {
          # Nix owns the version: an in-app update would replace the store
          # build with upstream's npm one.
          limits.updates.mode = lib.mkDefault "off";
          limits.telemetry = lib.mkDefault false;
          settings = lib.mkMerge [
            (lib.mkIf devices.enable {
              enableDeviceSupport = lock true;
              # The onboarding flow's whole job is enabling the hub, done above.
              deviceOnboardingCompleted = lock true;
            })
            { enableAgentDeviceAccess = lock devices.agentAccess; }
            { simlockDeviceHostsEnabled = lock devices.simlock.enable; }
          ];
        };
      }

      (lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = devices.simlock.hosts != {} -> devices.simlock.enable;
            message = "myNixOS.services.t3code.devices.simlock.hosts is ignored by t3code unless devices.simlock.enable is set.";
          }
          {
            # Each name is both t3code's host id and part of an opnix key,
            # which only takes camelCase; "local" is t3code's own.
            assertion = lib.all (n: builtins.match "[a-zA-Z0-9]+" n != null && n != "local") (lib.attrNames devices.simlock.hosts);
            message = "myNixOS.services.t3code.devices.simlock.hosts names must be alphanumeric and not \"local\".";
          }
        ];
        environment.etc."t3code/policy.json".source = policyFile;
      })

      # Only the background server seeds Simlock hosts. Owner, not a
      # `services` restart: opnix only restarts system units (see t3code.nix).
      (lib.mkIf server.enable {
        services.onepassword-secrets.secrets = lib.mapAttrs' (name: h:
          lib.nameValuePair (devices.simlock.secretName name) {
            reference = h.agentToken;
            owner = server.user;
            mode = "0400";
          }) devices.simlock.hosts;
      })

      # Same layout upstream's installer leaves: <home>/tools/<name>/<version>
      # with a `.install-complete` sentinel. Everything above the version
      # stays a real, user-owned dir: the server takes its maintenance lock in
      # there. Its pruner skips anything that isn't a real directory, so the
      # store links are never removed. L+ replaces an earlier npm install.
      (lib.mkIf (cfg.enable && devices.enable) {
        systemd.tmpfiles.settings."10-t3code" = lib.mkMerge (map (home: let
          owned = {
            d = {
              inherit (home) user;
              group = config.users.users.${home.user}.group;
              mode = "0700";
            };
          };
        in {
          "${home.path}" = owned;
          "${home.path}/tools" = owned;
        } // lib.concatMapAttrs (name: version: {
          "${home.path}/tools/${name}" = owned;
          "${home.path}/tools/${name}/${version}"."L+".argument = "${tools}/${name}/${version}";
        }) tools.versions) cfg.homes);
      })
    ];
  };
}
