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
          };
          postgresPassword =
            {
              reference = "op://Homelab/Postgres/password";
            }
            // servicesIf config.services.postgresql.enable ["postgresql"]
            // ownerIf "postgres" // groupIf "postgres";
          homelabControllerEnv = {
            reference = "op://Homelab/HomelabController/envFile";
          } // servicesIf config.myNixOS.services.homelab_system_controller.enable ["homelab_system_controller"];
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
          # Included by cramt's user nix.conf (modules/hm-bundles/general.nix)
          # for authenticated github.com tarball fetches. Flake inputs are
          # fetched by the evaluating *client*, not the daemon, so the file has
          # to be readable by the user running nix -- as 0600 root:root the
          # `!include` was a silent no-op and every fetch took the
          # unauthenticated 60/hr rate limit.
          nixAccessTokensConf =
            {
              reference = "op://Homelab/GitHub/nixAccessTokensConf";
              mode = "0640";
            }
            // groupIf "onepassword-secrets";
          discordBotToken = {
            reference = "op://Homelab/OpenClaw-Discord/botToken";
          };
          # The work cli-proxy-api pool, read by the `opencode` wrapper
          # (modules/hm-features/opencode.nix). Two fields rather than one
          # envFile because a 1Password field can't hold a newline.
          # Group-readable so the wrapper reads them as cramt, not root.
          opencodeUrl =
            {
              reference = "op://Homelab/OpenCode/url";
              mode = "0640";
            }
            // groupIf "onepassword-secrets";
          opencodeApiKey =
            {
              reference = "op://Homelab/OpenCode/apiKey";
              mode = "0640";
            }
            // groupIf "onepassword-secrets";
          # API key for cramt's cli-proxy-api pool on luna. luna's proxy accepts
          # it and every host's `claude` wrapper sends it
          # (modules/hm-features/claude-code.nix). Group-readable because both
          # sides run as cramt.
          cliProxyApiKey =
            {
              reference = "op://Homelab/CliProxyAPI/apiKey";
              mode = "0640";
            }
            // groupIf "onepassword-secrets";
          # Shared push credential for the metrics agents. Rendered on every
          # opnix host, so the 1Password item has to exist before any of them
          # deploy -- opnix fails the whole secret render if a reference is dead.
          metricsRemoteWritePassword =
            {
              reference = "op://Homelab/Metrics/remoteWritePassword";
            }
            // servicesIf config.services.prometheus.enableAgentMode ["prometheus"]
            // ownerIf "prometheus" // groupIf "prometheus";
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
        # vxn.rs WireGuard client creds. Gated: a personal VPN identity has no
        # business being rendered on the servers, and an ungated reference would
        # make every opnix host fail its render if the item ever goes away.
        // lib.optionalAttrs config.myNixOS.vpn.vxn.enable {
          vxnPrivateKey = {
            reference = "op://Homelab/VXN-WireGuard/privateKey";
          };
          vxnPresharedKey = {
            reference = "op://Homelab/VXN-WireGuard/presharedKey";
          };
        }
        # Gated so hosts without the portal don't fail their render if the
        # item is ever missing. Root-owned is fine: authelia reads them through
        # systemd LoadCredential.
        // lib.optionalAttrs config.myNixOS.services.authelia.enable (
          builtins.mapAttrs (_: field:
            {reference = "op://Homelab/Authelia/${field}";}
            // servicesIf true ["authelia-main"]) {
            autheliaJwtSecret = "jwtSecret";
            autheliaSessionSecret = "sessionSecret";
            autheliaStorageEncryptionKey = "storageEncryptionKey";
          }
        )
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
