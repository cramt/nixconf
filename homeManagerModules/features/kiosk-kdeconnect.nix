{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.myHomeManager.kiosk-kdeconnect;
  commandsJson = builtins.toJSON (
    builtins.mapAttrs (_: cmd: {
      inherit (cmd) name command;
    })
    cfg.commands
  );
in {
  options.myHomeManager.kiosk-kdeconnect = {
    commands = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name for the command";
          };
          command = lib.mkOption {
            type = lib.types.str;
            description = "Shell command to execute";
          };
        };
      });
      default = {};
      description = "Commands to expose via KDE Connect's run-command plugin";
    };
  };

  config = {
    services.kdeconnect.enable = true;

    home.activation.kdeconnect-commands = lib.mkIf (cfg.commands != {}) (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        KDECONNECT_DIR="$HOME/.config/kdeconnect"
        if [ -d "$KDECONNECT_DIR" ]; then
          for device_dir in "$KDECONNECT_DIR"/*/; do
            [ -d "$device_dir" ] || continue
            basename=$(basename "$device_dir")
            case "$basename" in
              *.pem|config) continue ;;
            esac

            cmd_dir="$device_dir/kdeconnect_runcommand"
            mkdir -p "$cmd_dir"
            cat > "$cmd_dir/config" << 'KDEEOF'
[General]
commands=${commandsJson}
KDEEOF
          done
        fi
      ''
    );
  };
}
