add_foundry_zips:
    #!/usr/bin/env nu
    ls ../nix-static/ | each { |it| nix-store --add-fixed sha256 $it.name } | each { |path| cachix push cramt $path }
    null

build_luna: add_foundry_zips
    nh os switch --target-host root@192.168.178.24 -H luna -- --fallback

build_ganymede:
    nh os switch --target-host root@192.168.178.47 -H ganymede -- --fallback

# Build the OpenWrt sysupgrade image for the Archer C5 v2 (titan).
# Flash result via the C5 v2's LuCI web UI → System → Backup / Flash Firmware.
build_titan:
    nix build .#titan-img

# Push UCI config to a running titan (Archer C5 v2 with OpenWrt).
# Requires titan to be reachable over SSH at the IP set in hosts/titan/dewclaw.nix.
deploy_titan:
    nix build .#titan-deploy
    ./result/bin/deploy-titan

clean_ruby:
    rm -rf ~/.local/share/gem/

update_flake:
    nix flake update

update_gems:
    (cd gems && bundle lock --update)

# Bump the from-source / prebuilt packages that live outside flake.lock and npins
# (hardcoded version + hash in packages/*/default.nix). nix-update follows each
# package's upstream latest release and rewrites version + hashes in place.
# steamlink is intentionally absent (no upstream version feed — see its default.nix).
update_packages:
    for pkg in agentsview agent-browser cockatrice; do \
      nix run nixpkgs#nix-update -- --flake "$pkg" || exit 1; \
    done

update:
    fwupdmgr update -y || true
    just update_flake
    just update_gems
    npins update
    just update_packages
    nh os switch

tf *args:
    #!/usr/bin/env bash
    export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/opnix-token)
    export PG_CONN_STR="postgres://terraformremotestate:$(op read 'op://Homelab/TerraformRemoteState/password')@$(op read 'op://Homelab/Infrastructure/lunaInternalAddress'):5432"
    tofu -chdir=infra {{args}}
