add_foundry_zips:
    #!/usr/bin/env nu
    ls ../nix-static/ | each { |it| nix-store --add-fixed sha256 $it.name }
    null

build_luna: add_foundry_zips
    nh os switch --target-host root@192.168.178.24 -H luna

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
    nvfetcher
    nh os switch
