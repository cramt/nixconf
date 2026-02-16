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

update:
    fwupdmgr update -y || true
    just update_flake
    just update_gems
    npins update
    nh os switch

tf *args:
    #!/usr/bin/env bash
    export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/opnix-token)
    export PG_CONN_STR="postgres://terraformremotestate:$(op read 'op://Homelab/TerraformRemoteState/password')@$(op read 'op://Homelab/Infrastructure/lunaInternalAddress'):5432"
    terraform -chdir=infra {{args}}
