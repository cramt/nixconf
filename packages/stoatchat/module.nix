# Stoatchat NixOS Module
#
# Deploys a full Stoatchat (Revolt-based) chat instance using Podman Quadlet.
#
# Prerequisites:
#   - quadlet-nix (github:SEIAROTg/quadlet-nix) nixosModules.quadlet must be
#     imported alongside this module.
#
# Minimal usage:
#   services.stoatchat = {
#     enable = true;
#     domain = "chat.example.com";
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.stoatchat;
  q = config.virtualisation.quadlet;
  net = q.networks.stoatchat.ref;

  pins = import ./npins;

  # Image reference from npins: "image_name:image_tag@image_digest"
  pinnedImage = name: let
    pin = pins.${name} {};
  in "${pin.image_name}:${pin.image_tag}@${pin.image_digest}";

  images = {
    mongo = cfg.images.mongo or (pinnedImage "mongo");
    redis = cfg.images.redis or (pinnedImage "keydb");
    rabbitmq = cfg.images.rabbitmq or (pinnedImage "rabbitmq");
    minio = cfg.images.minio or (pinnedImage "minio");
    minioCli = cfg.images.minioCli or (pinnedImage "minio-mc");
    caddy = cfg.images.caddy or (pinnedImage "caddy");
    server = cfg.images.server or (pinnedImage "server");
    bonfire = cfg.images.bonfire or (pinnedImage "bonfire");
    web = cfg.images.web or (pinnedImage "web");
    autumn = cfg.images.autumn or (pinnedImage "autumn");
    january = cfg.images.january or (pinnedImage "january");
    gifbox = cfg.images.gifbox or (pinnedImage "gifbox");
    crond = cfg.images.crond or (pinnedImage "crond");
    pushd = cfg.images.pushd or (pinnedImage "pushd");
  };

  tomlFormat = pkgs.formats.toml {};

  # Structured config with secret placeholders that get substituted at runtime
  revoltTomlTemplate = tomlFormat.generate "Revolt.toml.template" (recursiveUpdate {
    hosts = {
      app = "https://${cfg.domain}";
      api = "https://${cfg.domain}/api";
      events = "wss://${cfg.domain}/ws";
      autumn = "https://${cfg.domain}/autumn";
      january = "https://${cfg.domain}/january";
    };
    pushd.vapid = {
      private_key = "@VAPID_PRIVATE@";
      public_key = "@VAPID_PUBLIC@";
    };
    files = {
      encryption_key = "@FILE_ENCRYPTION_KEY@";
    };
  } cfg.settings);

  caddyfile = pkgs.writeText "Caddyfile" ''
    :80 {
      route /api* {
        uri strip_prefix /api
        reverse_proxy http://api:14702 {
          header_down Location "^/" "/api/"
        }
      }

      route /ws {
        uri strip_prefix /ws
        reverse_proxy http://events:14703 {
          header_down Location "^/" "/ws/"
        }
      }

      route /autumn* {
        uri strip_prefix /autumn
        reverse_proxy http://autumn:14704 {
          header_down Location "^/" "/autumn/"
        }
      }

      route /january* {
        uri strip_prefix /january
        reverse_proxy http://january:14705 {
          header_down Location "^/" "/january/"
        }
      }

      route /gifbox* {
        uri strip_prefix /gifbox
        reverse_proxy http://gifbox:14706 {
          header_down Location "^/" "/gifbox/"
        }
      }

      reverse_proxy http://web:5000
    }
  '';

  # Helper for Revolt application containers (mount Revolt.toml + join network)
  mkRevoltContainer = {
    image,
    aliases,
    extraConfig ? {},
  }:
    recursiveUpdate {
      containerConfig = {
        inherit image;
        volumes = ["${cfg.dataDir}/Revolt.toml:/Revolt.toml:ro"];
        networks = [net];
        networkAliases = aliases;
      };
    }
    extraConfig;

  inviteScript = pkgs.writeShellScriptBin "stoatchat-invite" ''
    if [ "$(id -u)" -ne 0 ]; then
      exec sudo "$0" "$@"
    fi
    CODE=$(${pkgs.openssl}/bin/openssl rand -hex 8)
    ${pkgs.podman}/bin/podman exec stoatchat-database mongosh --quiet revolt --eval "db.invites.insertOne({ _id: \"$CODE\" })" > /dev/null
    echo "$CODE"
  '';

  configUnit = "stoatchat-config.service";
in {
  options.services.stoatchat = {
    enable = mkEnableOption "Stoatchat (Revolt-based chat platform)";

    domain = mkOption {
      type = types.str;
      example = "chat.example.com";
      description = "Domain name for the Stoatchat instance. Caddy will obtain TLS certificates automatically.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/stoatchat";
      description = "Directory for persistent data (database, files, certificates, etc.).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open HTTP (80) and HTTPS (443) ports in the firewall.";
    };

    port = mkOption {
      type = types.port;
      default = 80;
      description = "Host port to publish the Caddy HTTP listener on.";
    };

    vapidKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a PEM-encoded EC P-256 private key file for VAPID web push. The public key is derived automatically. If null, a key is generated automatically in dataDir on first run.";
    };

    fileEncryptionKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing the encryption key for uploaded files (base64). If null, a key is generated automatically in dataDir on first run.";
    };

    minio = {
      rootUser = mkOption {
        type = types.str;
        default = "minioautumn";
        description = "MinIO root username.";
      };

      rootPassword = mkOption {
        type = types.str;
        default = "minioautumn";
        description = "MinIO root password. Only used internally between containers.";
      };
    };

    rabbitmq = {
      user = mkOption {
        type = types.str;
        default = "rabbituser";
        description = "RabbitMQ default username.";
      };

      password = mkOption {
        type = types.str;
        default = "rabbitpass";
        description = "RabbitMQ default password. Only used internally between containers.";
      };
    };

    images = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = ''
        Override container image references (bypasses npins).
        Available keys: mongo, redis, rabbitmq, minio, minioCli, caddy,
        server, bonfire, web, autumn, january, gifbox, crond, pushd.
      '';
      example = {
        server = "ghcr.io/revoltchat/server:latest";
      };
    };

    settings = mkOption {
      type = tomlFormat.type;
      default = {};
      description = ''
        Arbitrary Revolt.toml configuration as a Nix attrset, serialized to TOML.
        Merged on top of the base config (hosts, vapid, files sections).
        See https://github.com/revoltchat/backend/blob/main/crates/core/config/Revolt.toml
      '';
      example = {
        api.registration.invite_only = true;
        api.smtp = {
          host = "smtp.example.com";
          from_address = "noreply@example.com";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [inviteScript];

    # Persistent data directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/db 0700 root root -"
      "d ${cfg.dataDir}/minio 0700 root root -"
      "d ${cfg.dataDir}/rabbit 0700 root root -"
      "d ${cfg.dataDir}/caddy-data 0700 root root -"
      "d ${cfg.dataDir}/caddy-config 0700 root root -"
    ];

    networking.firewall = mkMerge [
      (mkIf cfg.openFirewall {
        allowedTCPPorts = [cfg.port];
      })
      {
        # Allow DNS resolution between containers on the bridge network
        interfaces."br-stoatchat".allowedUDPPorts = [53];
      }
    ];

    # Generate runtime config files from secrets before containers start
    systemd.services.stoatchat-config = {
      description = "Generate Stoatchat configuration from secrets";
      wantedBy = ["multi-user.target"];
      before = [
        "podman-stoatchat-rabbit.service"
        "podman-stoatchat-minio.service"
        "podman-stoatchat-api.service"
        "podman-stoatchat-events.service"
        "podman-stoatchat-autumn.service"
        "podman-stoatchat-january.service"
        "podman-stoatchat-gifbox.service"
        "podman-stoatchat-crond.service"
        "podman-stoatchat-pushd.service"
        "podman-stoatchat-createbuckets.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = let
          vapidKeyPath =
            if cfg.vapidKeyFile != null
            then toString cfg.vapidKeyFile
            else "${cfg.dataDir}/vapid.pem";
          fileKeyPath =
            if cfg.fileEncryptionKeyFile != null
            then toString cfg.fileEncryptionKeyFile
            else "${cfg.dataDir}/file-encryption.key";
        in pkgs.writeShellScript "stoatchat-generate-config" ''
          set -euo pipefail

          # Generate VAPID key if it doesn't exist
          VAPID_KEY="${vapidKeyPath}"
          if [ ! -f "$VAPID_KEY" ]; then
            ${pkgs.openssl}/bin/openssl ecparam -name prime256v1 -genkey -noout -out "$VAPID_KEY"
            chmod 600 "$VAPID_KEY"
          fi

          # Generate file encryption key if it doesn't exist
          FILE_KEY_PATH="${fileKeyPath}"
          if [ ! -f "$FILE_KEY_PATH" ]; then
            ${pkgs.openssl}/bin/openssl rand -base64 32 > "$FILE_KEY_PATH"
            chmod 600 "$FILE_KEY_PATH"
          fi

          VAPID_PRIVATE="$(${pkgs.openssl}/bin/openssl base64 -in "$VAPID_KEY" -A | tr -d '=')"
          VAPID_PUBLIC="$(${pkgs.openssl}/bin/openssl ec -in "$VAPID_KEY" -outform DER 2>/dev/null | tail --bytes 65 | ${pkgs.openssl}/bin/openssl base64 -A | tr '/+' '_-' | tr -d '=')"
          FILE_KEY="$(cat "$FILE_KEY_PATH")"
          MINIO_PASS="${cfg.minio.rootPassword}"
          RABBIT_PASS="${cfg.rabbitmq.password}"

          # Revolt.toml with secrets substituted
          ${pkgs.gnused}/bin/sed \
            -e "s|@VAPID_PRIVATE@|$VAPID_PRIVATE|g" \
            -e "s|@VAPID_PUBLIC@|$VAPID_PUBLIC|g" \
            -e "s|@FILE_ENCRYPTION_KEY@|$FILE_KEY|g" \
            "${revoltTomlTemplate}" > "${cfg.dataDir}/Revolt.toml"
          chmod 644 "${cfg.dataDir}/Revolt.toml"

          # Environment files for infrastructure containers
          printf 'MINIO_ROOT_USER=%s\nMINIO_ROOT_PASSWORD=%s\nMINIO_DOMAIN=minio\n' \
            "${cfg.minio.rootUser}" "$MINIO_PASS" > "${cfg.dataDir}/minio.env"
          chmod 644 "${cfg.dataDir}/minio.env"

          printf 'RABBITMQ_DEFAULT_USER=%s\nRABBITMQ_DEFAULT_PASS=%s\n' \
            "${cfg.rabbitmq.user}" "$RABBIT_PASS" > "${cfg.dataDir}/rabbit.env"
          chmod 644 "${cfg.dataDir}/rabbit.env"

          # Init script for createbuckets container
          printf '#!/bin/sh\nwhile ! /usr/bin/mc ready minio; do\n  /usr/bin/mc alias set minio http://minio:9000 %s %s\n  echo "Waiting for minio..." && sleep 1\ndone\n/usr/bin/mc mb --ignore-existing minio/revolt-uploads\n' \
            "${cfg.minio.rootUser}" "$MINIO_PASS" > "${cfg.dataDir}/create-buckets.sh"
          chmod 755 "${cfg.dataDir}/create-buckets.sh"
        '';
      };
    };

    virtualisation.quadlet = {
      networks.stoatchat.networkConfig = {
        driver = "bridge";
        interfaceName = "br-stoatchat";
      };

      containers = {
        # ── Infrastructure ────────────────────────────────────────────

        stoatchat-database = {
          autoStart = true;
          containerConfig = {
            image = images.mongo;
            volumes = ["${cfg.dataDir}/db:/data/db"];
            networks = [net];
            networkAliases = ["database"];
            healthCmd = ''echo 'db.runCommand("ping").ok' | mongosh localhost:27017/test --quiet'';
            healthInterval = "10s";
            healthTimeout = "10s";
            healthRetries = 5;
            healthStartPeriod = "10s";
          };
        };

        stoatchat-redis = {
          autoStart = true;
          containerConfig = {
            image = images.redis;
            networks = [net];
            networkAliases = ["redis"];
          };
        };

        stoatchat-rabbit = {
          autoStart = true;
          containerConfig = {
            image = images.rabbitmq;
            volumes = ["${cfg.dataDir}/rabbit:/var/lib/rabbitmq"];
            networks = [net];
            networkAliases = ["rabbit"];
            environmentFiles = ["${cfg.dataDir}/rabbit.env"];
            healthCmd = "rabbitmq-diagnostics -q ping";
            healthInterval = "10s";
            healthTimeout = "10s";
            healthRetries = 3;
            healthStartPeriod = "20s";
          };
          unitConfig = {
            Requires = [configUnit];
            After = [configUnit];
          };
        };

        stoatchat-minio = {
          autoStart = true;
          containerConfig = {
            image = images.minio;
            exec = "server /data";
            volumes = ["${cfg.dataDir}/minio:/data"];
            networks = [net];
            networkAliases = [
              "minio"
              "revolt-uploads.minio"
              # Legacy bucket aliases
              "attachments.minio"
              "avatars.minio"
              "backgrounds.minio"
              "icons.minio"
              "banners.minio"
              "emojis.minio"
            ];
            environmentFiles = ["${cfg.dataDir}/minio.env"];
          };
          unitConfig = {
            Requires = [configUnit];
            After = [configUnit];
          };
        };

        stoatchat-createbuckets = {
          containerConfig = {
            image = images.minioCli;
            networks = [net];
            volumes = ["${cfg.dataDir}/create-buckets.sh:/init.sh:ro"];
            entrypoint = "/bin/sh";
            exec = "/init.sh";
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          unitConfig = {
            Requires = [
              configUnit
              q.containers.stoatchat-minio.ref
            ];
            After = [
              configUnit
              q.containers.stoatchat-minio.ref
            ];
          };
        };

        # ── Reverse proxy ─────────────────────────────────────────────

        stoatchat-caddy = {
          autoStart = true;
          containerConfig = {
            image = images.caddy;
            publishPorts = [
              "${toString cfg.port}:80"
            ];
            volumes = [
              "${caddyfile}:/etc/caddy/Caddyfile:ro"
              "${cfg.dataDir}/caddy-data:/data"
              "${cfg.dataDir}/caddy-config:/config"
            ];
            networks = [net];
            networkAliases = ["caddy"];
          };
        };

        # ── Application services ──────────────────────────────────────

        stoatchat-api = mkRevoltContainer {
          image = images.server;
          aliases = ["api"];
          extraConfig = {
            autoStart = true;
            unitConfig = {
              Requires = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-redis.ref
                q.containers.stoatchat-rabbit.ref
              ];
              After = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-redis.ref
                q.containers.stoatchat-rabbit.ref
              ];
            };
          };
        };

        stoatchat-events = mkRevoltContainer {
          image = images.bonfire;
          aliases = ["events"];
          extraConfig = {
            autoStart = true;
            unitConfig = {
              Requires = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-redis.ref
              ];
              After = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-redis.ref
              ];
            };
          };
        };

        stoatchat-web = {
          autoStart = true;
          containerConfig = {
            image = images.web;
            networks = [net];
            networkAliases = ["web"];
            environments = {
              HOSTNAME = "https://${cfg.domain}";
              REVOLT_PUBLIC_URL = "https://${cfg.domain}/api";
            };
          };
        };

        stoatchat-autumn = mkRevoltContainer {
          image = images.autumn;
          aliases = ["autumn"];
          extraConfig = {
            autoStart = true;
            unitConfig = {
              Requires = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-createbuckets.ref
              ];
              After = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-createbuckets.ref
              ];
            };
          };
        };

        stoatchat-january = mkRevoltContainer {
          image = images.january;
          aliases = ["january"];
          extraConfig = {
            autoStart = true;
            unitConfig = {
              Requires = [configUnit];
              After = [configUnit];
            };
          };
        };

        stoatchat-gifbox = mkRevoltContainer {
          image = images.gifbox;
          aliases = ["gifbox"];
          extraConfig = {
            autoStart = true;
            unitConfig = {
              Requires = [configUnit];
              After = [configUnit];
            };
          };
        };

        stoatchat-crond = mkRevoltContainer {
          image = images.crond;
          aliases = ["crond"];
          extraConfig = {
            autoStart = true;
            unitConfig = {
              Requires = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-minio.ref
              ];
              After = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-minio.ref
              ];
            };
          };
        };

        stoatchat-pushd = mkRevoltContainer {
          image = images.pushd;
          aliases = ["pushd"];
          extraConfig = {
            autoStart = true;
            unitConfig = {
              Requires = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-redis.ref
                q.containers.stoatchat-rabbit.ref
              ];
              After = [
                configUnit
                q.containers.stoatchat-database.ref
                q.containers.stoatchat-redis.ref
                q.containers.stoatchat-rabbit.ref
              ];
            };
          };
        };
      };
    };
  };
}
