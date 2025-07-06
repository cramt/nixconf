{
  lib,
  config,
  inputs,
  outputs,
  myLib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS;
in {
  options.myNixOS.home-users = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        userConfig = lib.mkOption {
          default = ./../../home-manager/work.nix;
          example = "DP-1";
        };
        authorizedKeys = lib.mkOption {
          default = [];
        };
      };
    });
    default = {};
  };

  config = {
    programs.zsh.enable = true;
    programs.hyprland.enable = true;

    home-manager = {
      extraSpecialArgs = {
        inherit inputs;
        inherit myLib;
        inherit pkgs;
        outputs = inputs.self.outputs;
      };

      users =
        builtins.mapAttrs
        (name: user: {...}: {
          imports = [
            (import user.userConfig)
            outputs.homeManagerModules.default
          ];
        })
        (config.myNixOS.home-users);
    };

    users.users =
      (
        builtins.mapAttrs
        (
          name: user: {
            isNormalUser = true;
            initialPassword = "12345";
            description = "";
            shell = pkgs.zsh;
            extraGroups = [
              "libvirtd"
              "networkmanager"
              "wheel"
              "docker"
              "storage"
              "gamemode"
              "plugdev"
              "dailout"
            ];
            openssh.authorizedKeys.keys = user.authorizedKeys;
          }
        )
        (config.myNixOS.home-users)
      )
      // {
        root.openssh.authorizedKeys.keys = lib.lists.flatten (lib.attrsets.mapAttrsToList (name: user: user.authorizedKeys) config.myNixOS.home-users);
      };
  };
}
