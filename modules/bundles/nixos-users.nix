# NixOS multi-user bundle with home-manager integration
{ inputs, ... }: {
  flake.nixosModules."bundles.users" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS;
    outputs = inputs.self.outputs;
  in {
    options.myNixOS = {
      bundles.users.enable = lib.mkEnableOption "myNixOS.bundles.users";
      home-users = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            userConfig = lib.mkOption {
              default = ../../home-manager/work.nix;
              example = "DP-1";
            };
            authorizedKeys = lib.mkOption {
              default = [];
            };
          };
        });
        default = {};
      };
    };

    config = lib.mkIf cfg.bundles.users.enable {
      programs.zsh.enable = true;
      home-manager = {
        extraSpecialArgs = {
          inherit inputs;
        };
        users =
          builtins.mapAttrs
          (name: user: {...}: {
            imports =
              [
                (import user.userConfig)
                outputs.homeManagerModules.default
                inputs.nix-index-database.homeModules.nix-index
              ]
              ++ builtins.attrValues outputs.homeManagerModules.features
              ++ builtins.attrValues outputs.homeManagerModules.bundles;
          })
          cfg.home-users;
      };
      users = {
        groups.plugdev.name = "plugdev";
        users =
          (builtins.mapAttrs
            (name: user: {
              isNormalUser = true;
              initialPassword = "12345";
              description = "";
              shell = pkgs.zsh;
              extraGroups = [
                "libvirtd"
                "networkmanager"
                "wheel"
                "pipewire"
                "docker"
                "storage"
                "gamemode"
                "plugdev"
                "dailout"
                "systemd-journal"
              ];
              openssh.authorizedKeys.keys = user.authorizedKeys;
            })
            cfg.home-users)
          // {
            root.openssh.authorizedKeys.keys = lib.lists.flatten (lib.attrsets.mapAttrsToList (name: user: user.authorizedKeys) cfg.home-users);
          };
      };
    };
  };
}
