add_foundry_zips:
    #!/usr/bin/env nu
    ls ../foundry_zips/ | each { |it| nix-store --add-fixed sha256 $it.name }

build_luna: add_foundry_zips
    nixos-rebuild switch --flake .#luna --target-host root@192.168.0.103

clean_ruby:
    rm -rf ~/.local/share/gem/
