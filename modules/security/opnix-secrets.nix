# 1Password secrets via opnix
{ ... }: {
  flake.nixosModules."features.opnix-secrets" = { config, lib, ... }:
  let
    hasUser = name: builtins.hasAttr name config.users.users;
    hasGroup = name: builtins.hasAttr name config.users.groups;
    ownerIf = name: lib.optionalAttrs (hasUser name) {owner = name;};
    groupIf = name: lib.optionalAttrs (hasGroup name) {group = name;};
    # Only attach restart wiring for services that are actually enabled on this
    # host. Otherwise opnix emits a `systemd.services.<name>` stub with only
    # After=/Wants= (no ExecStart), which systemd rejects as bad-setting and
    # NixOS activation reports as "Failed to start <svc>: bad unit file setting".
    servicesIf = enabled: names: lib.optionalAttrs enabled {services = names;};
  in {
    options.myNixOS.opnix-secrets.enable = lib.mkEnableOption "myNixOS.opnix-secrets";
    config = lib.mkIf config.myNixOS.opnix-secrets.enable {
      users.users =
        builtins.mapAttrs (name: _: {
          extraGroups = ["onepassword-secrets"];
        })
        config.myNixOS.home-users;

      services.onepassword-secrets = {
        enable = true;
        tokenFile = "/etc/opnix-token";
        secrets = {
          tailscalePreauthKey = {
            reference = "op://Homelab/Tailscale/preauthKey";
          } // servicesIf config.services.tailscale.enable ["tailscaled"];
          cloudflareCredsEnv = {
            reference = "op://Homelab/Cloudflare/credsEnv";
          } // servicesIf (config.security.acme.certs ? "turn.cramt.dk") ["acme-turn.cramt.dk"];
          postgresPassword =
            {
              reference = "op://Homelab/Postgres/password";
            }
            // servicesIf config.services.postgresql.enable ["postgresql"]
            // ownerIf "postgres" // groupIf "postgres";
          homelabControllerEnv = {
            reference = "op://Homelab/HomelabController/envFile";
          } // servicesIf config.myNixOS.services.homelab_system_controller.enable ["homelab_system_controller"];
          valheimEnv = {
            reference = "op://Homelab/Valheim/envFile";
          };
          curseForgeEnv = {
            reference = "op://Homelab/CurseForge/envFile";
          };
          garageEnv = {
            reference = "op://Homelab/Garage/envFile";
          } // servicesIf config.services.garage.enable ["garage"];
          jellyfinCramtPassword = {
            reference = "op://Homelab/JellyfinUsers/cramtPassword";
            mode = "0640";
          } // groupIf "jellarr";
          jellyfinHannahPassword = {
            reference = "op://Homelab/JellyfinUsers/hannahPassword";
            mode = "0640";
          } // groupIf "jellarr";
          cockatricePassword = {
            reference = "op://Homelab/Cockatrice/password";
          };
          cockatriceEnv = {
            reference = "op://Homelab/Cockatrice/envFile";
          };
          matrixSharedSecret =
            {
              reference = "op://Homelab/Matrix/sharedSecret";
            }
            // servicesIf config.services.coturn.enable ["coturn"]
            // ownerIf "turnserver" // groupIf "turnserver";
          matrixSecretEnv = {
            reference = "op://Homelab/Matrix/conduitEnv";
          };
          nixAccessTokensConf = {
            reference = "op://Homelab/GitHub/nixAccessTokensConf";
          };
          discordBotToken = {
            reference = "op://Homelab/OpenClaw-Discord/botToken";
          };
          # Shared push credential for the metrics agents. Rendered on every
          # opnix host, so the 1Password item has to exist before any of them
          # deploy -- opnix fails the whole secret render if a reference is dead.
          metricsRemoteWritePassword = {
            reference = "op://Homelab/Metrics/remoteWritePassword";
          } // servicesIf config.services.prometheus.enableAgentMode ["prometheus"];
          # Grafana refuses to start without one (no default since v11); it
          # signs sessions and encrypts datasource credentials. Same 1Password
          # item as the push password, different field.
          grafanaSecretKey =
            {
              reference = "op://Homelab/Metrics/grafanaSecretKey";
            }
            // servicesIf config.services.grafana.enable ["grafana"]
            // ownerIf "grafana" // groupIf "grafana";
          terraformRemotePassword =
            {
              reference = "op://Homelab/TerraformRemoteState/password";
            }
            // servicesIf config.services.postgresql.enable ["postgresql"]
            // ownerIf "postgres" // groupIf "postgres";
        }
        # Coding-agent SSH key. Gated on the headless-key opt-in so this reused
        # personal SSH private key only renders where agents actually need it
        # on disk (luna) — not on desktop hosts that also run the server but
        # have 1Password's agent, and not on every other opnix host. Owned by cramt because the server runs as a
        # `systemd --user` unit and its agents sign/push as that user. No
        # `services` restart wiring: opnix restarts *system* units, but t3code is
        # a user unit — a dangling `services = ["t3code"]` would make opnix emit
        # a stub system unit with no ExecStart and break activation. After
        # rotating the key, restart the user service by hand:
        #   systemctl --user -M cramt@ restart t3code
        // lib.optionalAttrs config.myNixOS.services.t3code.onDiskSshKey.enable {
          # Name kept from the paseo era: same 1Password item, same key, and
          # renaming would only churn the rendered path for no gain.
          paseoSshKey = {
            reference = "op://Homelab/Paseo/sshPrivateKey";
            owner = "cramt";
            mode = "0600";
          };
        };
      };
    };
  };
}
