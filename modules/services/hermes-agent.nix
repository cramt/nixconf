# Hermes Agent (Nous Research) — self-hosted autonomous agent, pointed at the
# local M365 Copilot proxy so Hermes' brain runs through the Microsoft 365
# Copilot-backed OpenAI-compatible endpoint.
#
# Runs in CONTAINER mode: a persistent writable Ubuntu layer so the agent can
# apt/pip/npm install and self-modify. The upstream module runs the container
# with --network=host, so 127.0.0.1:<proxy> reaches the local proxy directly.
#
# Pairs with myNixOS.services.m365-copilot-proxy on the same host (see the
# assertion). LiteLLM/gpt-oss-120b remains available as an alternative backend —
# swap settings.model.base_url back to the litellm port to use it.
#
# Discord is off by default. To enable later:
#   1. Create a Hermes Discord bot and store its token in 1Password:
#        op://Homelab/Hermes-Discord/envFile  ->  DISCORD_BOT_TOKEN=...
#   2. Set `myNixOS.services.hermes-agent.discord.enable = true;`
#      (rebuilds the package with the `messaging` deps and wires the token).
{ inputs, ... }: {
  flake.nixosModules."services.hermes-agent" = { config, lib, ... }:
  let
    cfg = config.myNixOS.services.hermes-agent;
    proxyPort = config.port-selector.ports.m365-copilot-proxy;
  in {
    imports = [ inputs.hermes-agent.nixosModules.default ];

    options.myNixOS.services.hermes-agent = {
      enable = lib.mkEnableOption "myNixOS.services.hermes-agent";
      discord.enable = lib.mkEnableOption ''
        Hermes Discord integration. Needs op://Homelab/Hermes-Discord/envFile
        containing DISCORD_BOT_TOKEN'';
      discord.allowedUserIds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "149996010314137600" ];
        description = ''
          Discord numeric user IDs allowed to talk to Hermes (DISCORD_ALLOWED_USERS).
          Hermes denies all users unless allowlisted. Numeric IDs avoid needing the
          Server Members privileged intent. Never use allow-all on a terminal-capable
          agent — scope it to your own ID.
        '';
      };
      discord.homeChannelId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "1465064573840130289";
        description = ''
          Discord channel ID for the home channel (DISCORD_HOME_CHANNEL), where
          cron results and cross-platform messages are delivered. Set this
          declaratively — `/sethome` can't persist against the read-only config.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [{
        assertion = config.myNixOS.services.m365-copilot-proxy.enable;
        message = ''
          myNixOS.services.hermes-agent expects myNixOS.services.m365-copilot-proxy
          enabled on the same host — it points at the local proxy endpoint.
        '';
      }];

      services.hermes-agent = {
        enable = true;
        container.enable = true;
        container.backend = "docker";
        container.hostUsers = [ "cramt" ];
        # Expose the `hermes` CLI system-wide so cramt can drive it on the host.
        addToSystemPackages = true;

        # Discord (messaging) deps are only pulled into the package build when
        # the integration is enabled, to keep the default build lean.
        extraDependencyGroups = lib.optionals cfg.discord.enable [ "messaging" ];

        # Allowlist + home channel (non-secret) go through the .env env path.
        # Without the allowlist Hermes denies every Discord user; the home
        # channel can't be set via /sethome against the read-only config.
        environment =
          lib.optionalAttrs (cfg.discord.enable && cfg.discord.allowedUserIds != [ ])
            { DISCORD_ALLOWED_USERS = lib.concatStringsSep "," cfg.discord.allowedUserIds; }
          // lib.optionalAttrs (cfg.discord.enable && cfg.discord.homeChannelId != null)
            { DISCORD_HOME_CHANNEL = cfg.discord.homeChannelId; };

        settings.model = {
          # Explicit GPT reasoning tone via the M365 Copilot proxy. This mirrors
          # pi's default on hosts with the proxy enabled and avoids the high-variance
          # `magic` auto-router.
          default = "gpt-5.5-think-deeper";
          provider = "custom";   # any OpenAI-compatible endpoint
          base_url = "http://127.0.0.1:${toString proxyPort}/v1";
          # The proxy runs without auth; the OpenAI client still wants a
          # non-empty key. This is a placeholder, not a secret.
          api_key = "m365";
        };

        # Discord auto-enables in the gateway when DISCORD_BOT_TOKEN is present.
        environmentFiles = lib.optional cfg.discord.enable
          config.services.onepassword-secrets.secretPaths.hermesDiscordEnv;
      };

      services.onepassword-secrets.secrets = lib.mkIf cfg.discord.enable {
        hermesDiscordEnv = {
          reference = "op://Homelab/Hermes-Discord/envFile";
          services = [ "hermes-agent" ];
        };
      };

      # The upstream module seeds $HERMES_HOME/.env from environmentFiles in an
      # *activation script*, which runs before opnix-secrets.service renders the
      # secret — so on every deploy the `[ -f secret ]` test fails and the Discord
      # token is silently dropped from .env. Re-seed it just before hermes starts,
      # ordered after opnix has rendered it, so deploys stay idempotent. Runs on
      # every (re)start (no RemainAfterExit); the grep guard avoids duplicates.
      systemd.services.hermes-discord-env = lib.mkIf cfg.discord.enable {
        description = "Re-seed Hermes Discord token into .env (after opnix)";
        after = [ "opnix-secrets.service" ];
        requires = [ "opnix-secrets.service" ];
        before = [ "hermes-agent.service" ];
        requiredBy = [ "hermes-agent.service" ];
        serviceConfig.Type = "oneshot";
        script = ''
          envFile="${config.services.hermes-agent.stateDir}/.hermes/.env"
          secret="${config.services.onepassword-secrets.secretPaths.hermesDiscordEnv}"
          if [ -f "$secret" ] && [ -f "$envFile" ] \
             && ! grep -q '^DISCORD_BOT_TOKEN=' "$envFile"; then
            { echo ""; cat "$secret"; } >> "$envFile"
          fi
        '';
      };
    };
  };
}
