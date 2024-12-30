add_foundry_zips:
    #!/usr/bin/env nu
    ls ../foundry_zips/ | each { |it| nix-store --add-fixed sha256 $it.name }
    null

build_luna: add_foundry_zips
    nixos-rebuild switch --flake .#luna --target-host root@192.168.0.103

clean_ruby:
    rm -rf ~/.local/share/gem/

update_flake:
    nix flake update

update_gems:
    (cd gems && bundle lock --update)
    (cd gems && bundix)

update:
    just update_flake
    just update_gems
    nvfetcher
    nh os switch
