# NixOS multi-user bundle with home-manager integration
{ inputs, ... }: {
  flake.nixosModules."bundles.users" = { config, lib, pkgs, hostDir, ... }:
  let
    cfg = config.myNixOS;
    outputs = inputs.self.outputs;
    hostHome = hostDir + "/home.nix";
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
              type = lib.types.listOf lib.types.str;
              default = (import ../../myLib/keys.nix).alex;
            };
          };
        });
        # Single-user fleet: every host's user is cramt, configured by the
        # home.nix sitting next to its configuration.nix. Hosts that need
        # something else just set this themselves.
        default = lib.optionalAttrs (builtins.pathExists hostHome) {
          cramt.userConfig = hostHome;
        };
      };
    };

    config = lib.mkIf cfg.bundles.users.enable {
      programs.zsh.enable = true;
      home-manager = {
        extraSpecialArgs = {
          inherit inputs;
        };
        # Move a pre-existing real file aside (→ <name>.hm-bak) instead of
        # aborting activation when HM wants to manage a path that already has an
        # unmanaged file (e.g. a stale ~/.config/zen/default/user.js). Matches
        # eros's setting.
        backupFileExtension = "hm-bak";
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
                "dialout"
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
