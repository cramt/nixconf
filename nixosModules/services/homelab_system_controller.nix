{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.myNixOS.services.homelab_system_controller;
  secrets = (import ../../secrets.nix).homelab_system_controller;
in {
  options.myNixOS.services.homelab_system_controller = {
    databaseUrl = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the sqlite db
      '';
    };
  };
  config = {
    systemd.services.homelab_system_controller = {
      enable = true;
      script = "${inputs.homelab_system_controller.packages.${pkgs.system}.host}/bin/host";
      environment = {
        DATABASE_URL = cfg.databaseUrl;
        DISCORD_TOKEN = secrets.discord_token;
        ALLOWED_GUILD = secrets.allowed_guild;
        LISTEN_PORT = "1622";
        SYSTEMCTL_PATH = "${pkgs.systemd}/bin/systemctl";
      };
      description = "Runs homelab system controller host";
      wantedBy = ["network-online.target"];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
