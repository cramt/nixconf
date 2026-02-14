{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-ruby-downgrade.url = "github:nixos/nixpkgs/nixos-25.11";
    nixarr.url = "github:nix-media-server/nixarr/cramt/jellyfin-users";
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    claude-code.url = "github:sadjow/claude-code-nix";

    opencode = {
      url = "github:anomalyco/opencode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    nh.url = "github:nix-community/nh";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    astal = {
      url = "github:aylur/astal";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ags = {
      url = "github:aylur/ags";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.astal.follows = "astal";
    };

    hyprshell = {
      url = "github:H3rmt/hyprshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cosmic-manager = {
      url = "github:HeitorAugustoLN/cosmic-manager";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    NonSteamLaunchers = {
      url = "github:moraroy/NonSteamLaunchers-On-Steam-Deck/main";
      flake = false;
    };

    yazi.url = "github:sxyazi/yazi";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-colors.url = "github:misterio77/nix-colors";

    nur.url = "github:nix-community/NUR";

    nix-ld = {
      url = "github:Mic92/nix-ld";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    foundryvtt.url = "github:reckenrode/nix-foundryvtt";

    darkmingo-cockactrice-theme = {
      url = "github:mingomongo/DarkMingo-Theme-for-Cockatrice";
      flake = false;
    };

    homelab_system_controller = {
      url = "github:cramt/homelab_system_controller";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git_update_notifier = {
      url = "github:cramt/git_update_notifier";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    probe-rs-rules = {
      url = "github:jneem/probe-rs-rules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser.url = "github:0xc000022070/zen-browser-flake";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opnix = {
      url = "github:brizzbuzz/opnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    flake-utils,
    nixpkgs,
    self,
    ...
  } @ inputs: let
    # super simple boilerplate-reducing
    # lib with a bunch of functions
    myLib = import ./myLib/default.nix {inherit inputs;};
  in
    (with myLib; {
      nixosConfigurations = {
        saturn = mkSystem ./hosts/saturn/configuration.nix;
        mars = mkSystem ./hosts/mars/configuration.nix;
        luna = mkSystem ./hosts/luna/configuration.nix;
        eros = mkSystem ./hosts/eros/configuration.nix;
        # titan = mkSystem ./hosts/titan/configuration.nix;
      };

      homeManagerModules.default = ./homeManagerModules;
      nixosModules.default = ./nixosModules;
    })
    // (flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
      };
    in {
      packages = {
        eros-img =
          pkgs.runCommand "eros.img" {
            nativeBuildInputs = [
              pkgs.zstd
              pkgs.util-linux
              pkgs.jq
              pkgs.mtools
            ];
          } ''
                set -euo pipefail

                mkdir -p "$out"

                # Locate the produced compressed image from the sd-card build output.
                imgZst="$(ls ${self.nixosConfigurations.eros.config.system.build.images.sd-card}/sd-image/*.img.zst)"

                # Decompress to a stable filename.
                ${pkgs.zstd}/bin/unzstd -c "$imgZst" > "$out/eros.img"

                # Read partition table as JSON and compute byte offset of partition 1 (FIRMWARE).
                sectorsize="$(${pkgs.util-linux}/bin/sfdisk -J "$out/eros.img" | ${pkgs.jq}/bin/jq -r '.partitiontable.sectorsize')"
                start="$(${pkgs.util-linux}/bin/sfdisk -J "$out/eros.img" | ${pkgs.jq}/bin/jq -r '.partitiontable.partitions[0].start')"
                offset="$(( start * sectorsize ))"

                # Write the firmware config we want.
                cat > "$TMPDIR/config.txt" <<'EOF'
            dtoverlay=vc4-kms-v3d
            gpu_mem=128
            disable_overscan=1
            EOF

                # Overwrite /config.txt in the firmware FAT partition without mounting.
                # mtools uses the "image@@offset" syntax to address a partition inside an image.
                ${pkgs.mtools}/bin/mcopy -o -i "$out/eros.img@@$offset" "$TMPDIR/config.txt" ::config.txt

                # Optional sanity check (lists root of the firmware partition)
                ${pkgs.mtools}/bin/mdir -i "$out/eros.img@@$offset" ::
          '';
      };
    }));
}
