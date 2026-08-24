{ inputs, ... }: {
  hmModules.default = { pkgs, lib, config, ... }:
  let
    types_float = lib.mkOptionType {
      name = "float";
      check = builtins.isFloat;
    };
  in {
    imports = [
      inputs.nvf.homeManagerModules.default
      inputs.cosmic-manager.homeManagerModules.cosmic-manager
      inputs.zen-browser.homeModules.beta
      inputs.hyprshell.homeModules.hyprshell
      # niri-flake's homeModules.config is injected into home-manager.sharedModules
      # by its nixosModule (see modules/desktop/niri.nix); importing it here too
      # would double-declare programs.niri.* and conflict.
      # noctalia's own homeModules.default is NOT imported: home-manager
      # upstreamed the same module (nix-community/home-manager#9757), and both
      # declare programs.noctalia.*, which is a duplicate-option eval error.
      # HM's copy is the flake module verbatim apart from validateConfig ->
      # checkConfig (we set neither) and package defaulting to pkgs.noctalia.
      # Re-add the flake module — with disabledModules on HM's — only if
      # noctalia starts shipping options HM's copy lacks.
      ({ lib, config, ... }: {
        # home-manager stopped inferring cursor generation from
        # `home.pointerCursor.{name,package}` being set and will drop the
        # implicit path (nix-community/home-manager#6492); stylix's HM cursor
        # module still only sets those. Declare the enable here so cursors keep
        # generating instead of silently vanishing on a future HM bump.
        # Remove once stylix sets `home.pointerCursor.enable` itself.
        config = lib.mkIf config.stylix.enable {
          home.pointerCursor.enable = true;
        };
      })
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
      config = {
        allowUnfree = true;
      };
    };
  };
}
