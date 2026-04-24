# 1Password secrets via opnix
{ ... }: {
  flake.nixosModules."features.opnix-secrets" = { config, lib, ... }:
  let
    hasUser = name: builtins.hasAttr name config.users.users;
    hasGroup = name: builtins.hasAttr name config.users.groups;
    ownerIf = name: lib.optionalAttrs (hasUser name) {owner = name;};
    groupIf = name: lib.optionalAttrs (hasGroup name) {group = name;};
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
            services = ["tailscaled"];
          };
          cloudflareCredsEnv = {
            reference = "op://Homelab/Cloudflare/credsEnv";
            services = ["acme-turn.cramt.dk"];
          };
          postgresPassword =
            {
              reference = "op://Homelab/Postgres/password";
              services = ["postgresql"];
            }
            // ownerIf "postgres" // groupIf "postgres";
          homelabControllerEnv = {
            reference = "op://Homelab/HomelabController/envFile";
            services = ["homelab_system_controller"];
          };
          valheimEnv = {
            reference = "op://Homelab/Valheim/envFile";
          };
          curseForgeEnv = {
            reference = "op://Homelab/CurseForge/envFile";
          };
          minioCredsEnv = {
            reference = "op://Homelab/Minio/credsEnv";
            services = ["minio"];
          };
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
              services = ["coturn"];
            }
            // ownerIf "turnserver" // groupIf "turnserver";
          matrixSecretEnv = {
            reference = "op://Homelab/Matrix/conduitEnv";
          };
          nixAccessTokensConf = {
            reference = "op://Homelab/GitHub/nixAccessTokensConf";
          };
          terraformRemotePassword =
            {
              reference = "op://Homelab/TerraformRemoteState/password";
              services = ["postgresql"];
            }
            // ownerIf "postgres" // groupIf "postgres";
        };
      };
    };
  };
}
