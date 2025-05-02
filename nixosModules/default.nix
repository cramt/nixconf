{
  pkgs,
  config,
  lib,
  inputs,
  outputs,
  myLib,
  ...
}: let
  cfg = config.myNixOS;

  # Taking all modules in ./features and adding enables to them
  features =
    myLib.extendModules
    (name: {
      extraOptions = {
        myNixOS.${name}.enable = lib.mkEnableOption "enable my ${name} configuration";
      };

      configExtension = config: (lib.mkIf cfg.${name}.enable config);
    })
    (myLib.filesIn ./features);

  # Taking all module bundles in ./bundles and adding bundle.enables to them
  bundles =
    myLib.extendModules
    (name: {
      extraOptions = {
        myNixOS.bundles.${name}.enable = lib.mkEnableOption "enable ${name} module bundle";
      };

      configExtension = config: (lib.mkIf cfg.bundles.${name}.enable config);
    })
    (myLib.filesIn ./bundles);

  services =
    myLib.extendModules
    (name: {
      extraOptions = {
        myNixOS.services.${name}.enable = lib.mkEnableOption "enable ${name} service";
      };

      configExtension = config: (lib.mkIf cfg.services.${name}.enable config);
    })
    (myLib.filesIn ./services);
in {
  imports =
    [
      inputs.home-manager.nixosModules.home-manager
      inputs.stylix.nixosModules.stylix
      inputs.foundryvtt.nixosModules.foundryvtt
    ]
    ++ features
    ++ bundles
    ++ services;

  config = {
    stylix.enable = true;
    nix.package = pkgs.lix;
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["cramt" "root"];
      substituters = [
        "https://nix-gaming.cachix.org"
        "https://yazi.cachix.org"
      ];
      trusted-public-keys = [
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
        "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
      ];
    };
    programs.nix-ld.enable = true;
    nixpkgs = {
      overlays = [
        inputs.nur.overlays.default
        (final: prev: {
          lazygit = prev.writeScriptBin "lazygit" ''
            echo 'a' | ${prev.gnupg}/bin/gpg --sign -u alex.cramt@gmail.com > /dev/null && ${prev.lazygit}/bin/lazygit
          '';
        })
        (final: prev: {
          cosmic-comp = prev.cosmic-comp.overrideAttrs (old: {
            patches = (old.patches or []) ++ [../patches/no_ssd.patch];
          });
        })
        (final: prev: {
          julia = prev.julia.withPackages ["JuliaFormatter" "LanguageServer"];
        })
        (final: prev: {
          docker = prev.docker.override {
            buildxSupport = true;
          };
        })
        (final: prev: {
          rocmPackages = inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.rocmPackages;
        })
      ];
      config = {
        allowUnfree = true;
      };
    };
  };
}
