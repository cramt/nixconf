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
  options.myNixOS = {
    userName = lib.mkOption {
      default = "cramt";
      description = ''
        username
      '';
    };

    userConfig = lib.mkOption {
      default = ./../../home-manager/work.nix;
      description = ''
        home-manager config path
      '';
    };

    userNixosSettings = lib.mkOption {
      default = {};
      description = ''
        NixOS user settings
      '';
    };
  };

  config = {
    programs.zsh.enable = true;
    programs.hyprland = {
      enable = true;
      package = null;
      withUWSM = true;
    };

    services = {
      displayManager = {
        defaultSession = "hyprland";
      };
    };

    home-manager = {
      extraSpecialArgs = {
        inherit inputs;
        inherit myLib;
        inherit pkgs;
        outputs = inputs.self.outputs;
      };
      users = {
        ${cfg.userName} = {...}: {
          imports = [
            (import cfg.userConfig)
            outputs.homeManagerModules.default
          ];
        };
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
          "plugdev"
          "dailout"
        ];
      }
      // cfg.userNixosSettings;
  };
}
