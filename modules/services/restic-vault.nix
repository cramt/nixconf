# Encrypted restic backup of /vault to mega.nz via rclone.
#
# Before enabling on a host:
#
#   1. Create the 1Password item op://Homelab/ResticVault with two fields:
#        password   - restic repo password (generate with `openssl rand -base64 32`)
#        rcloneEnv  - envfile contents, e.g.:
#                       RCLONE_MEGA_USER=you@example.com
#                       RCLONE_MEGA_PASS=<output of `rclone obscure '<plaintext>'`>
#
#   2. Set `myNixOS.services.restic-vault.enable = true;` on the host.
#
#   3. nh os switch -H <host>. The first scheduled run initializes the repo on
#      mega and uploads. Trigger ad-hoc with `systemctl start restic-backups-vault`.
{...}: {
  flake.nixosModules."services.restic-vault" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.restic-vault;
    stateDir = "/var/lib/restic-vault";
    rcloneConfPath = "${stateDir}/rclone.conf";

    # Declarative rclone config. The secret pieces are env-var placeholders
    # that envsubst expands at service start from the opnix-loaded
    # EnvironmentFile, so the structure stays auditable in git while the
    # credentials stay in 1Password.
    rcloneConfTemplate = pkgs.writeText "restic-vault-rclone.conf.template" ''
      [mega]
      type = mega
      user = ''${RCLONE_MEGA_USER}
      pass = ''${RCLONE_MEGA_PASS}
    '';

    renderRcloneConf = pkgs.writeShellScript "restic-vault-render-rclone-conf" ''
      set -euo pipefail
      install -d -m 0700 ${stateDir}
      ${pkgs.gettext}/bin/envsubst < ${rcloneConfTemplate} > ${rcloneConfPath}
      chmod 0600 ${rcloneConfPath}
    '';
  in {
    options.myNixOS.services.restic-vault = {
      enable = lib.mkEnableOption "encrypted restic backup of /vault to mega.nz";
      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["/vault"];
        description = "Paths to back up.";
      };
      remotePath = lib.mkOption {
        type = lib.types.str;
        default = "restic-vault";
        description = "Folder name on mega holding the restic repo.";
      };
      schedule = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 03:00:00";
        description = "systemd OnCalendar expression for the daily backup.";
      };
      pruneOpts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 6"
        ];
        description = "Options passed to `restic forget --prune` after each backup.";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.tmpfiles.rules = [
        "d ${stateDir} 0700 root root -"
      ];

      services.restic.backups.vault = {
        repository = "rclone:mega:${cfg.remotePath}";
        passwordFile = config.services.onepassword-secrets.secretPaths.resticVaultPassword;
        environmentFile = config.services.onepassword-secrets.secretPaths.resticVaultRcloneEnv;
        rcloneConfigFile = rcloneConfPath;
        paths = cfg.paths;
        initialize = true;
        timerConfig = {
          OnCalendar = cfg.schedule;
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
        pruneOpts = cfg.pruneOpts;
        extraBackupArgs = [
          "--exclude-caches"
          "--one-file-system"
        ];
      };

      # Render rclone.conf before restic starts. The `+` prefix runs as root
      # regardless of the unit's User=, so we can write to /var/lib.
      systemd.services."restic-backups-vault".serviceConfig.ExecStartPre =
        lib.mkBefore ["+${renderRcloneConf}"];

      # opnix secrets are co-located with the service so they're only fetched
      # on hosts where the backup is actually enabled.
      services.onepassword-secrets.secrets = {
        resticVaultPassword = {
          reference = "op://Homelab/ResticVault/password";
          services = ["restic-backups-vault"];
        };
        resticVaultRcloneEnv = {
          reference = "op://Homelab/ResticVault/rcloneEnv";
          services = ["restic-backups-vault"];
        };
      };
    };
  };
}
