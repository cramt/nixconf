add_foundry_zips:
    #!/usr/bin/env nu
    ls ../nix-static/ | each { |it| nix-store --add-fixed sha256 $it.name } | each { |path| cachix push cramt $path }
    null

build_luna: 
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

# Print the paseo quick-connect pairing QR + link from the luna daemon.
# Pair the desktop/phone client with this. Run as cramt so it reads the
# daemon's ~/.paseo state; absolute binary path dodges non-interactive PATH.
paseo_pair:
    ssh cramt@192.168.178.24 /run/current-system/sw/bin/paseo daemon pair

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
    nix run nixpkgs#nix-update -- --flake agentsview
    nix run nixpkgs#nix-update -- --flake agent-browser
    nix run nixpkgs#nix-update -- --flake cockatrice

# Bump every pinned source (flake.lock, gems, npins, packages). Run daily by
# .github/workflows/update.yml, which pushes the result to the `update` branch
# as a PR and prebuilds it into cachix — merge that PR to update.
update:
    just update_flake
    just update_gems
    npins update
    just update_packages

tf *args:
    #!/usr/bin/env bash
    export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/opnix-token)
    export PG_CONN_STR="postgres://terraformremotestate:$(op read 'op://Homelab/TerraformRemoteState/password')@$(op read 'op://Homelab/Infrastructure/lunaInternalAddress'):5432"
    tofu -chdir=infra {{args}}
