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
      script = ''
        DATABASE_URL=${cfg.databaseUrl} DISCORD_TOKEN=$(cat ${config.sops.secrets."homelab_discord_bot/discord_token".path}) ${inputs.homelab_discord_bot.packages.${pkgs.system}.homelab_discord_bot}/bin/homelab_discord_bot
      '';
      description = "Runs homelab discord bot";
      wantedBy = [ "network-online.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
