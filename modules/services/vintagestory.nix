{inputs, ...}: {
  flake.nixosModules."services.vintagestory" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.vintagestory;
  in {
    imports = [inputs.vintagestory-nix.nixosModules.default];

    options.myNixOS.services.vintagestory = {
      enable = lib.mkEnableOption "myNixOS.services.vintagestory";
      dataDir = lib.mkOption {
        type = lib.types.str;
        description = "where worlds, mods and serverconfig.json live";
      };
      admins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "account names whitelisted and given the admin role on every server start";
      };
      whitelist = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "account names whitelisted on every server start (admins are implicitly)";
      };
    };

    config = lib.mkIf cfg.enable {
      services.vintagestory = {
        enable = true;
        package = pkgs.vintagestoryPackages.latest;
        # The game's default port: clients type it, so port-selector can't pick it.
        port = 42420;
        openFirewall = true;
      };

      # Upstream hardcodes state under /var/lib; bind dataDir over it so worlds
      # land on a big disk. StateDirectory still gets created first, then this
      # is mounted on top inside the unit's namespace.
      systemd.tmpfiles.settings.vintagestory.${cfg.dataDir}.d = {
        user = "vintagestory";
        group = "vintagestory";
        mode = "0750";
      };
      systemd.services.vintagestory.serviceConfig.BindPaths = [
        "${cfg.dataDir}:/var/lib/${config.services.vintagestory.dataPath}"
      ];

      # Whitelist and roles live in Playerdata/*.json keyed by the auth server's
      # player UID, so they can't be pre-seeded from a name. Instead feed the
      # idempotent console commands through upstream's stdin FIFO once the
      # server is up. One command per write: lines written together get read
      # as a single command.
      systemd.services.vintagestory-players = lib.mkIf (cfg.admins ++ cfg.whitelist != []) {
        description = "Whitelist and op Vintagestory players";
        wantedBy = ["vintagestory.service"];
        after = ["vintagestory.service"];
        bindsTo = ["vintagestory.service"];
        path = [config.systemd.package];
        serviceConfig = {
          Type = "oneshot";
          # First boot of a new world spends minutes in world generation.
          TimeoutStartSec = "30min";
        };
        script = ''
          id=$(systemctl show -P InvocationID vintagestory.service)
          until journalctl -o cat _SYSTEMD_INVOCATION_ID="$id" | grep -q "Dedicated Server now running"; do
            sleep 5
          done
          send() {
            printf '%s\n' "$1" > /run/vintagestory.socket
            sleep 2
          }
          for name in ${lib.escapeShellArgs (cfg.admins ++ cfg.whitelist)}; do
            send "/whitelist add $name"
          done
          for name in ${lib.escapeShellArgs cfg.admins}; do
            send "/op $name"
          done
        '';
      };
    };
  };
}
