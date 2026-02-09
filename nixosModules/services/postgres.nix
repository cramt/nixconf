{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.postgres;
  secrets = import ../../secrets.nix;

  port = config.port-selector.ports.postgresql;
in {
  options.myNixOS.services.postgres = {
    applicationUsers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "name";
            };
            passwordFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "path to file containing the password";
            };
            open = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "open outside";
            };
          };
        }
      );
      description = ''
        users
      '';
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
    };
  };
  config = {
    port-selector.set-ports."5432" = "postgresql";
    networking.firewall.allowedTCPPorts = [port];
    services.postgresql = {
      enable = true;
      ensureDatabases = builtins.map (x: x.name) cfg.applicationUsers;
      enableTCPIP = true;
      settings = {
        ssl = true;
      };
      settings.port = port;
      ensureUsers =
        builtins.map (x: {
          name = x.name;
          ensureDBOwnership = true;
          ensureClauses = {
            login = true;
          };
        })
        cfg.applicationUsers;
      authentication = lib.strings.concatMapStrings (x:
        if x.open
        then ""
        else ''
          hostssl ${x.name} ${x.name} 0.0.0.0/0 scram-sha-256
        '')
      cfg.applicationUsers;
      dataDir = cfg.dataDir;
    };
    systemd.services.postgresql = {
      preStart = lib.mkAfter ''
        mkdir -p ${cfg.dataDir}
        if ! test -e ${cfg.dataDir}/server.key; then
            ${pkgs.openssl}/bin/openssl req -new -x509 -days 365 -nodes -text -out ${cfg.dataDir}/server.crt -keyout ${cfg.dataDir}/server.key -subj "/CN=postgres.${secrets.domain}"
            chmod 0400 ${cfg.dataDir}/server.key
        fi
      '';
      postStart = lib.mkAfter ''
        POSTGRES_PASSWORD=$(cat ${config.services.onepassword-secrets.secretPaths.postgresPassword})
        ${config.services.postgresql.package}/bin/psql -c "ALTER USER \"postgres\" WITH PASSWORD '$POSTGRES_PASSWORD';" -d postgres
        ${lib.strings.concatMapStrings (x:
          if x.passwordFile == null
          then ""
          else ''
            USER_PASSWORD=$(cat ${x.passwordFile})
            ${config.services.postgresql.package}/bin/psql -c "ALTER USER \"${x.name}\" WITH PASSWORD '$USER_PASSWORD';" -d postgres
          '')
        cfg.applicationUsers}
      '';
    };
  };
}
