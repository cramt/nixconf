{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  secrets = import ../../secrets.nix;
  hasClawdbotInput = inputs ? nix-clawdbot;
in {
  imports = lib.optionals hasClawdbotInput [
    inputs.nix-clawdbot.homeManagerModules.clawdbot
  ];

  config = lib.mkIf (config.myHomeManager.clawdbot.enable && hasClawdbotInput) {
    # Write secrets to files that clawdbot expects
    home.file.".secrets/clawdbot-discord-token".text = secrets.clawdbot.discord_token;
    home.file.".secrets/clawdbot-anthropic-key".text = secrets.clawdbot.anthropic_api_key;

    programs.clawdbot = {
      enable = true;

      # Anthropic API key configuration
      providers.anthropic = {
        apiKeyFile = "${config.home.homeDirectory}/.secrets/clawdbot-anthropic-key";
      };

      # Discord configuration
      providers.discord = {
        enable = true;
        botTokenFile = "${config.home.homeDirectory}/.secrets/clawdbot-discord-token";
        allowedGuilds = [secrets.clawdbot.discord_guild_id];
      };

      # Enable systemd service on Linux
      systemd.enable = pkgs.stdenv.isLinux;
      launchd.enable = pkgs.stdenv.isDarwin;
    };
  };
}
