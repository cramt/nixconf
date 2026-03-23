{ inputs, ... }: {
  hmModules.default = { pkgs, lib, config, ... }:
  let
    types_float = lib.mkOptionType {
      name = "float";
      check = builtins.isFloat;
    };
  in {
    imports = [
      inputs.nixvim.homeModules.nixvim
      inputs.nvf.homeManagerModules.default
      inputs.cosmic-manager.homeManagerModules.cosmic-manager
      inputs.zen-browser.homeModules.beta
      inputs.hyprshell.homeModules.hyprshell
      inputs.niri-flake.homeModules.config
      inputs.noctalia-shell.homeModules.default
      ({ lib, config, ... }: {
        config = lib.mkIf (config.stylix.enable && config.programs.neovide.enable) {
          stylix.targets.neovide.enable = lib.mkForce false;
          programs.neovide.settings.font = {
            normal = [ config.stylix.fonts.monospace.name ];
            size = config.stylix.fonts.sizes.terminal;
          };
          programs.neovim.initLua = ''
            if vim.g.neovide then
              vim.g.neovide_normal_opacity = ${toString config.stylix.opacity.terminal}
            end
          '';
        };
      })
      {
        options.myHomeManager.monitors = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                workspace = lib.mkOption { type = lib.types.ints.unsigned; };
                transform = lib.mkOption { type = lib.types.ints.unsigned; };
                refresh_rate = lib.mkOption { type = lib.types.nullOr types_float; default = null; };
                port = lib.mkOption { type = lib.types.str; };
                name = lib.mkOption { type = lib.types.str; };
                pos = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      x = lib.mkOption { type = lib.types.int; };
                      y = lib.mkOption { type = lib.types.int; };
                    };
                  };
                };
                res = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      width = lib.mkOption { type = lib.types.ints.unsigned; };
                      height = lib.mkOption { type = lib.types.ints.unsigned; };
                    };
                  };
                };
              };
            }
          );
        };
      }
    ];
    nixpkgs = {
      overlays = import ../../overlays inputs;
      config = { allowUnfree = true; };
    };
  };
}
