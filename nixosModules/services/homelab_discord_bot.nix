{ inputs, pkgs, config, lib, ... }:
let
  cfg = config.myNixOS.services.homelab_discord_bot;
in
{
  options.myNixOS.services.homelab_discord_bot = {
    databaseUrl = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the sqlite db
      '';
    };
  };
  config = {
    systemd.services.homelab_discord_bot = {
      enable = true;
      script =
        let
          envs = {
            DATABASE_URL = cfg.databaseUrl;
            DISCORD_TOKEN = "$(cat ${config.sops.secrets."homelab_discord_bot/discord_token".path})";
            ALLOWED_GUILD = "$(cat ${config.sops.secrets."homelab_discord_bot/allowed_guild".path})";
            SYSTEMCTL_PATH = "${pkgs.systemd}/bin/systemctl";
          };
          envCommand = lib.strings.concatStringsSep " " (lib.attrsets.mapAttrsToList (name: value: "${name}=${value}") envs);
          binary = "${inputs.homelab_discord_bot.packages.${pkgs.system}.homelab_discord_bot}/bin/homelab_discord_bot";
        in
        "${envCommand} ${binary}";
      description = "Runs homelab discord bot";
      wantedBy = [ "network-online.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
