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
          terraformRemotePassword =
            {
              reference = "op://Homelab/TerraformRemoteState/password";
            }
            // servicesIf config.services.postgresql.enable ["postgresql"]
            // ownerIf "postgres" // groupIf "postgres";
        };
      };
    };
  };
}
