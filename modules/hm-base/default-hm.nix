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
      # niri-flake's homeModules.config is injected into home-manager.sharedModules
      # by its nixosModule (see modules/desktop/niri.nix); importing it here too
      # would double-declare programs.niri.* and conflict.
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
      config = {
        allowUnfree = true;
        # TEMPORARY: vesktop pins pnpm_10_29_2 (insecure) as its *build-time*
        # dep. Upstream nixpkgs already switched vesktop to pnpm_10 in commit
        # 4b3d28a (2026-06-29), but the nixos-unstable channel hasn't advanced
        # past it yet. This is build-time only (pnpm isn't in vesktop's runtime
        # closure) and keeps the Hydra cache hit.
        # NOTE TO FUTURE SELF: if you're here after bumping nixpkgs, check
        # `nix eval` — once the channel has the fix, DELETE this line.
        permittedInsecurePackages = ["pnpm-10.29.2"];
      };
    };
  };
}
