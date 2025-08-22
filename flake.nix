{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs";
    nixpkgs-ancient.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-ruby-downgrade.url = "github:nixos/nixpkgs/nixos-25.05";
    nixarr.url = "git+file:///home/cramt/code/nixarr";

    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

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
      #url = "github:nix-community/stylix";
      url = "github:Hobr/stylix";
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

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
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
        terra = mkSystem ./hosts/terra/configuration.nix;
        saturn = mkSystem ./hosts/saturn/configuration.nix;
        mars = mkSystem ./hosts/mars/configuration.nix;
        luna = mkSystem ./hosts/luna/configuration.nix;
        eros = mkSystem ./hosts/eros/configuration.nix;
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
        eros-img = pkgs.runCommand "eros-img" {} ''
          ls ${self.nixosConfigurations.eros.config.formats.sd-aarch64}
          echo "hello" > $out
          # TODO: uncompress with unzstd -d
        '';
      };
    }));
}
