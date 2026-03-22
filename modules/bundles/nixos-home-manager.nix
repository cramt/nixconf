# NixOS single-user home-manager setup (deprecated, prefer bundles.users)
{ inputs, ... }: {
  flake.nixosModules."bundles.home-manager" = { config, lib, pkgs, myLib, ... }:
  let
    cfg = config.myNixOS;
    outputs = inputs.self.outputs;
  in {
    options.myNixOS = {
      bundles.home-manager.enable = lib.mkEnableOption "myNixOS.bundles.home-manager";
      userName = lib.mkOption {
        default = "cramt";
        description = "username";
      };
      userConfig = lib.mkOption {
        default = ../../home-manager/work.nix;
        description = "home-manager config path";
      };
      userNixosSettings = lib.mkOption {
        default = {};
        description = "NixOS user settings";
      };
    };

    config = lib.mkIf cfg.bundles.home-manager.enable {
      programs.zsh.enable = true;
      programs.hyprland = {
        enable = true;
        package = null;
        withUWSM = true;
      };
      services.displayManager.defaultSession = "COSMIC";

      home-manager = {
        extraSpecialArgs = {
          inherit inputs myLib pkgs;
          outputs = inputs.self.outputs;
        };
        users.${cfg.userName} = {...}: {
          imports =
            [
              (import cfg.userConfig)
              outputs.homeManagerModules.default
              inputs.nix-index-database.homeModules.nix-index
            ]
            ++ builtins.attrValues outputs.homeManagerModules.features
            ++ builtins.attrValues outputs.homeManagerModules.bundles;
        };
      };

      users.users.${cfg.userName} =
        {
          isNormalUser = true;
          initialPassword = "12345";
          description = cfg.userName;
          shell = pkgs.zsh;
          extraGroups = [
            "libvirtd"
            "networkmanager"
            "wheel"
            "pipewire"
            "plugdev"
            "dailout"
            "input"
            "audio"
            "render"
          ];
        }
        // cfg.userNixosSettings;
    };
  };
}
