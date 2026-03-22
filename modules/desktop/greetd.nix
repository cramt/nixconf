# Greetd auto-login display manager
{ ... }: {
  flake.nixosModules."features.greetd" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.greetd;
  in {
    options.myNixOS.greetd = {
      enable = lib.mkEnableOption "myNixOS.greetd";
      command = lib.mkOption {
        type = lib.types.str;
        default = "uwsm start -e -D Hyprland hyprland.desktop";
        description = "Session command to run on autologin";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = config.myNixOS.userName;
        description = "User to autologin as";
      };
    };
    config = lib.mkIf cfg.enable {
      services.greetd = {
        enable = true;
        settings.default_session = {
          command = cfg.command;
          user = cfg.user;
        };
      };
      environment.systemPackages = [pkgs.tuigreet];
    };
  };
}
