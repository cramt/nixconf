{
  pkgs,
  system,
  inputs,
  config,
  lib,
  myLib,
  ...
}: let
  cfg = config.myHomeManager;

  # Taking all modules in ./features and adding enables to them
  features =
    myLib.extendModules
    (name: {
      extraOptions = {
        myHomeManager.${name}.enable = lib.mkEnableOption "enable my ${name} configuration";
      };

      configExtension = config: (lib.mkIf cfg.${name}.enable config);
    })
    (myLib.filesIn ./features);

  # Taking all module bundles in ./bundles and adding bundle.enables to them
  bundles =
    myLib.extendModules
    (name: {
      extraOptions = {
        myHomeManager.bundles.${name}.enable = lib.mkEnableOption "enable ${name} module bundle";
      };

      configExtension = config: (lib.mkIf cfg.bundles.${name}.enable config);
    })
    (myLib.filesIn ./bundles);
in {
  imports =
    [
      inputs.chaotic.homeManagerModules.default
      inputs.nixvim.homeManagerModules.nixvim
      inputs.nvf.homeManagerModules.default
      inputs.cosmic-manager.homeManagerModules.cosmic-manager
      inputs.zen-browser.homeModules.beta
      {
        options.myHomeManager.monitors = lib.mkOption {
          default = {};
          description = ''
            monitor setup
          '';
        };
      }
    ]
    ++ features
    ++ bundles;
  nixpkgs = {
    overlays = [
      inputs.nur.overlays.default
      (final: prev: {
        julia = prev.julia.withPackages ["JuliaFormatter" "LanguageServer"];
      })
      (final: prev: {
        cosmic-comp = prev.cosmic-comp.overrideAttrs (old: {
          patches = (old.patches or []) ++ [../patches/no_ssd.patch];
        });
      })
      (final: prev: {
        docker = prev.docker.override {
          buildxSupport = true;
        };
      })
    ];
    config = {
      allowUnfree = true;
    };
  };
}
