{ pkgs, host ? "192.168.178.24", port ? 22535 }: pkgs.writeShellScriptBin "open-openclaw" ''
  set -euo pipefail

  host="${host}"
  port="${toString port}"
  token_file="/var/lib/yelliv/token.env"

  token=$(${pkgs.openssh}/bin/ssh "root@$host" \
    "${pkgs.gnugrep}/bin/grep -oP 'OPENCLAW_GATEWAY_TOKEN=\K.*' $token_file" 2>/dev/null) || {
    echo "Failed to read token from $host:$token_file — is yelliv running?" >&2
    exit 1
  }

  if [[ -z "$token" ]]; then
    echo "Could not parse token from $host:$token_file" >&2
    exit 1
  fi

  url="http://''${host}:''${port}/?token=''${token}"
  echo "$url" | ${pkgs.wl-clipboard}/bin/wl-copy
  echo "Copied to clipboard, opening browser..."
  ${pkgs.xdg-utils}/bin/xdg-open "$url"
''
