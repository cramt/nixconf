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

update_t3code_deps:
    #!/usr/bin/env bash
    set -euo pipefail
    pkg="packages/t3code/default.nix"
    # Invalidate node modules FOD hash, then build to get the correct one
    sed -i 's|outputHash = "sha256-[^"]*"|outputHash = lib.fakeHash|' "$pkg"
    echo "t3code: fetching new node modules hash..."
    node_hash=$(nix build .#t3code 2>&1 | sed -n 's/.*got: *\(sha256-[^ ]*\).*/\1/p')
    if [ -z "$node_hash" ]; then
        echo "ERROR: could not extract node modules hash from build output"
        exit 1
    fi
    sed -i "s|lib.fakeHash|\"$node_hash\"|" "$pkg"
    echo "t3code: node modules hash updated"

update:
    fwupdmgr update -y || true
    just update_flake
    just update_gems
    npins update
    just update_t3code_deps
    nh os switch

tf *args:
    #!/usr/bin/env bash
    export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/opnix-token)
    export PG_CONN_STR="postgres://terraformremotestate:$(op read 'op://Homelab/TerraformRemoteState/password')@$(op read 'op://Homelab/Infrastructure/lunaInternalAddress'):5432"
    tofu -chdir=infra {{args}}
