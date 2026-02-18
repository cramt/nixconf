{
  pkgs,
  inputs,
  lib,
  myLib,
  ...
}: let
  types_float = lib.mkOptionType {
    name = "float";
    check = builtins.isFloat;
  };
in {
  imports =
    [
      inputs.nixvim.homeModules.nixvim
      inputs.nvf.homeManagerModules.default
      inputs.cosmic-manager.homeManagerModules.cosmic-manager
      inputs.zen-browser.homeModules.beta
      inputs.hyprshell.homeModules.hyprshell
      {
        options.myHomeManager.monitors = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                workspace = lib.mkOption {
                  type = lib.types.ints.unsigned;
                };
                transform = lib.mkOption {
                  type = lib.types.ints.unsigned;
                };
                refresh_rate = lib.mkOption {
                  type = lib.types.nullOr types_float;
                  default = null;
                };
                port = lib.mkOption {
                  type = lib.types.str;
                };
                name = lib.mkOption {
                  type = lib.types.str;
                };
                pos = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      x = lib.mkOption {
                        type = lib.types.int;
                      };
                      y = lib.mkOption {
                        type = lib.types.int;
                      };
                    };
                  };
                };
                res = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      width = lib.mkOption {
                        type = lib.types.ints.unsigned;
                      };
                      height = lib.mkOption {
                        type = lib.types.ints.unsigned;
                      };
                    };
                  };
                };
              };
            }
          );
        };
      }
    ]
    ++ (myLib.filesIn ./fixes);
  nixpkgs = {
    overlays = [
      inputs.nur.overlays.default
      (final: prev: {
        julia = prev.julia.withPackages ["JuliaFormatter" "LanguageServer"];
      })
      (final: prev: {
        cosmic-comp = prev.cosmic-comp.overrideAttrs (old: {
          patches = (old.patches or []) ++ [../patches/no_ssd.patch];
          doCheck = false;
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
