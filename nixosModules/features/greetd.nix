{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.greetd;
in {
  options.myNixOS.greetd = {
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

  config = {
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = cfg.command;
          user = cfg.user;
        };
      };
    };

    # Fallback greeter in case the default session crashes
    environment.systemPackages = [pkgs.tuigreet];
  };
}
