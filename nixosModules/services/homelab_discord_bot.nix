{ inputs, pkgs, config, lib, ... }:
let
  cfg = config.myNixOS.services.homelab_discord_bot;
  package = inputs.homelab_discord_bot.packages.${pkgs.system}.homelab_discord_bot.overrideAttrs (prevAttrs: {
    nativeBuildInputs = (prevAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeBinaryWrapper ];

    postInstall = (prevAttrs.postInstall or "") + ''
      wrapProgram $out/bin/homelab_discord_bot --set "DATABASE_URL" "${cfg.databaseUrl}"
    '';
  });
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
      description = "Runs homelab discord bot";
      wantedBy = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${package}/bin/homelab_discord_bot";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
