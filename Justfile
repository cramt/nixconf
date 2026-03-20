add_foundry_zips:
    #!/usr/bin/env nu
    ls ../nix-static/ | each { |it| nix-store --add-fixed sha256 $it.name }
    null

build_luna: add_foundry_zips
    nh os switch --target-host root@192.168.178.24 -H luna -- --fallback

build_ganymede:
    nh os switch --target-host root@192.168.178.47 -H ganymede -- --fallback

clean_ruby:
    rm -rf ~/.local/share/gem/

update_flake:
    nix flake update

update_gems:
    (cd gems && bundle lock --update)

update_t3code:
    #!/usr/bin/env bash
    set -euo pipefail
    pkg="packages/t3code/default.nix"
    current=$(grep 'version = ' "$pkg" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    latest=$(curl -sf https://api.github.com/repos/pingdotgg/t3code/releases/latest | jq -r '.tag_name | ltrimstr("v")')
    if [ "$current" = "$latest" ]; then
        echo "t3code already at $latest"
        exit 0
    fi
    echo "t3code: $current -> $latest"
    url="https://github.com/pingdotgg/t3code/releases/download/v${latest}/T3-Code-${latest}-x86_64.AppImage"
    hash=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null | xargs nix hash convert --hash-algo sha256 --to sri)
    sed -i "s|version = \"$current\"|version = \"$latest\"|" "$pkg"
    sed -i "s|hash = \".*\"|hash = \"$hash\"|" "$pkg"
    echo "t3code updated to $latest"

update:
    fwupdmgr update -y || true
    just update_flake
    just update_gems
    just update_t3code
    npins update
    nh os switch

tf *args:
    #!/usr/bin/env bash
    export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/opnix-token)
    export PG_CONN_STR="postgres://terraformremotestate:$(op read 'op://Homelab/TerraformRemoteState/password')@$(op read 'op://Homelab/Infrastructure/lunaInternalAddress'):5432"
    tofu -chdir=infra {{args}}
