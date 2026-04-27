{ pkgs }: pkgs.writeShellScriptBin "open-openclaw" ''
  set -euo pipefail

  token_file="/var/lib/yelliv/token.env"

  if [[ ! -f "$token_file" ]]; then
    echo "Token file not found at $token_file — is yelliv running?" >&2
    exit 1
  fi

  token=$(${pkgs.gnugrep}/bin/grep -oP 'OPENCLAW_GATEWAY_TOKEN=\K.*' "$token_file")

  if [[ -z "$token" ]]; then
    echo "Could not read token from $token_file" >&2
    exit 1
  fi

  url="http://localhost:22535/?token=''${token}"
  echo "$url" | ${pkgs.wl-clipboard}/bin/wl-copy
  echo "Copied to clipboard, opening browser..."
  ${pkgs.xdg-utils}/bin/xdg-open "$url"
''
