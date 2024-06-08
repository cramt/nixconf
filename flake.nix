{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.05";
    # downgrade to 0.49.0 solargraph as 0.50 requires strscan 3.0.9 which i cant get to work due to it being a pre-installed gem from ruby itself
    nixpkgs-ruby-downgrade.url = "github:nixos/nixpkgs/52c874987156f13ef08993618ea8bfb0531c0463";

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

    stylix.url = "github:danth/stylix";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neorg-overlay.url = "github:nvim-neorg/nixpkgs-neorg-overlay";

    foundryvtt.url = "github:reckenrode/nix-foundryvtt";

    darkmingo-cockactrice-theme = {
      url = "github:mingomongo/DarkMingo-Theme-for-Cockatrice";
      flake = false;
    };
  };

  outputs = { ... } @ inputs:
    let
      # super simple boilerplate-reducing
      # lib with a bunch of functions
      myLib = import ./myLib/default.nix { inherit inputs; };
    in
    with myLib; {
      nixosConfigurations = {
        terra = mkSystem ./hosts/terra/configuration.nix;
        io = mkSystem ./hosts/io/configuration.nix;
        mars = mkSystem ./hosts/mars/configuration.nix;
      };

      homeManagerModules.default = ./homeManagerModules;
      nixosModules.default = ./nixosModules;
    };
}

