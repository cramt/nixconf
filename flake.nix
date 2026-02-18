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

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

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

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      ./flake/lib.nix
      ./flake/hosts.nix
      ./flake/packages.nix
      ./flake/exported-modules.nix
    ];
    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
