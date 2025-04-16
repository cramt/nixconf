{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.postgres;
  secrets = import ../../secrets.nix;
  initialScript = pkgs.writeText "init.sql" ''
    ALTER USER "postgres" WITH PASSWORD '${secrets.postgres_password}';
  '';
  upsertScript = pkgs.writeText "init.sql" (lib.strings.concatMapStrings (x:
    if x.password == null
    then ""
    else ''alter user "${x.name}" with password '${x.password}';'')
  cfg.applicationUsers);
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
            password = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "password";
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
    networking.firewall.allowedTCPPorts = [5432];
    services.postgresql = {
      enable = true;
      ensureDatabases = builtins.map (x: x.name) cfg.applicationUsers;
      initialScript = initialScript;
      enableTCPIP = true;
      settings = {
        ssl = true;
      };
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
      preStart = lib.mkBefore ''
        mkdir -p ${cfg.dataDir}
        if ! test -e ${cfg.dataDir}/server.key; then
            ${pkgs.openssl}/bin/openssl req -new -x509 -days 365 -nodes -text -out ${cfg.dataDir}/server.crt -keyout ${cfg.dataDir}/server.key -subj "/CN=postgres.${secrets.domain}"
            chmod 0400 ${cfg.dataDir}/server.key
        fi
      '';
      postStart = lib.mkAfter ''
        $PSQL -f "${upsertScript}" -d postgres
      '';
    };
  };
}
