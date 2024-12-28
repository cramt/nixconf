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
      script = let
        envs = {
          DATABASE_URL = cfg.databaseUrl;
          DISCORD_TOKEN = "$(cat ${config.sops.secrets."homelab_system_controller/discord_token".path})";
          ALLOWED_GUILD = "$(cat ${config.sops.secrets."homelab_system_controller/allowed_guild".path})";
          SYSTEMCTL_PATH = "${pkgs.systemd}/bin/systemctl";
        };
        envCommand = lib.strings.concatStringsSep " " (lib.attrsets.mapAttrsToList (name: value: "${name}=${value}") envs);
        binary = "${inputs.homelab_system_controller.packages.${pkgs.system}.host}/bin/host";
      in "${envCommand} ${binary}";
      description = "Runs homelab system controller host";
      wantedBy = ["network-online.target"];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
