# Owner-only passkey gate for the admin UIs behind caddy. Which vhosts it guards
# is decided per entry in myNixOS.services.caddy.serviceMap (`forward-auth`),
# not here -- this module only runs the Authelia instance they point at.
#
# One user, file backend: the household's other people log into the apps that
# have real accounts (jellyfin, jellyseerr) and never see this.
{...}: {
  flake.nixosModules."services.authelia" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.authelia;
    caddyDomain = config.myNixOS.services.caddy.domain;
    port = config.port-selector.ports.authelia;
    secretPaths = config.services.onepassword-secrets.secretPaths;
    autheliaUrl = "https://${cfg.subdomain}.${caddyDomain}";

    # The argon2id digest is not a secret (same reasoning as the metrics bcrypt
    # hash), so the users file can live in the store.
    usersFile = (pkgs.formats.yaml {}).generate "authelia-users.yml" {
      users.${cfg.user.name} = {
        displayname = cfg.user.name;
        email = cfg.user.email;
        password = cfg.user.hashedPassword;
      };
    };
  in {
    options.myNixOS.services.authelia = {
      enable = lib.mkEnableOption "myNixOS.services.authelia";
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "auth";
        description = ''
          Portal vhost. Gets its A record from caddy.subdomains.
        '';
      };
      user = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "cramt";
        };
        email = lib.mkOption {
          type = lib.types.str;
          default = (import ../../myLib/site.nix).email;
        };
        hashedPassword = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            argon2id digest from `authelia crypto hash generate argon2`. The
            password is only for enrolling the first passkey; day to day the
            login is the passkey alone.
          '';
        };
      };
    };

    config = lib.mkIf cfg.enable {
      # Root-owned is fine: authelia reads them through systemd LoadCredential.
      services.onepassword-secrets.secrets = lib.mapAttrs (_: field: {
        reference = "op://Homelab/Authelia/${field}";
        services = ["authelia-main"];
      }) {
        autheliaJwtSecret = "jwtSecret";
        autheliaSessionSecret = "sessionSecret";
        autheliaStorageEncryptionKey = "storageEncryptionKey";
      };
      assertions = [
        {
          assertion = cfg.user.hashedPassword != null;
          message = "myNixOS.services.authelia.user.hashedPassword is unset; generate one with `authelia crypto hash generate argon2`.";
        }
      ];

      port-selector.auto-assign = ["authelia"];

      services.authelia.instances.main = {
        enable = true;
        # Read by systemd's LoadCredential as root, so opnix's root-only
        # default mode is fine.
        secrets = {
          jwtSecretFile = secretPaths.autheliaJwtSecret;
          sessionSecretFile = secretPaths.autheliaSessionSecret;
          storageEncryptionKeyFile = secretPaths.autheliaStorageEncryptionKey;
        };
        settings = {
          server.address = "tcp://127.0.0.1:${toString port}/";
          authentication_backend = {
            file.path = toString usersFile;
            # The users file is in the read-only store; there is nothing to
            # reset a password into.
            password_reset.disable = true;
          };
          webauthn = {
            disable = false;
            enable_passkey_login = true;
            # A user-verified passkey (biometric/PIN) counts as both factors,
            # so the day-to-day login is the passkey alone.
            experimental_enable_passkey_uv_two_factors = true;
            display_name = "cramt.dk";
          };
          # Caddy only asks about vhosts that opted in, so a blanket policy is
          # the whole access model. two_factor rather than one_factor: the
          # password alone shouldn't get in, and Authelia hides the passkey
          # settings entirely when nothing requires a second factor.
          access_control.default_policy = "two_factor";
          session.cookies = [
            {
              domain = caddyDomain;
              authelia_url = autheliaUrl;
            }
          ];
          storage.local.path = "/var/lib/authelia-main/db.sqlite3";
          # Identity verification for enrolling a passkey lands here instead of
          # email. It's needed once per new device, so reading it over ssh beats
          # carrying SMTP creds. Each prompt overwrites the file and revokes the
          # previous code, so only the newest one in it is valid.
          notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";
        };
      };

      myNixOS.services.caddy.serviceMap.${cfg.subdomain} = {inherit port;};
    };
  };
}
