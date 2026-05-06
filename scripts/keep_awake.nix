{ pkgs }: pkgs.writeShellScriptBin "keep-awake" ''
  set -euo pipefail

  if [ $# -eq 0 ]; then
    echo "usage: keep-awake <command> [args...]" >&2
    exit 2
  fi

  exec ${pkgs.systemd}/bin/systemd-inhibit \
    --what=idle:sleep:handle-lid-switch \
    --who=keep-awake \
    --why="keep-awake: $*" \
    -- "$@"
''
