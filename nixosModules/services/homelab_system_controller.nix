{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.myNixOS.services.homelab_system_controller;
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
      script = "${inputs.homelab_system_controller.packages.${pkgs.stdenv.hostPlatform.system}.host}/bin/host";
      environment = {
        DATABASE_URL = cfg.databaseUrl;
        LISTEN_PORT = "1622";
        SYSTEMCTL_PATH = "${pkgs.systemd}/bin/systemctl";
        RTSP_STREAM = "dummy";
      };
      description = "Runs homelab system controller host";
      wantedBy = ["network-online.target"];
      serviceConfig = {
        EnvironmentFile = config.services.onepassword-secrets.secretPaths.homelabControllerEnv;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
