# Hermes Agent (Nous Research) — self-hosted autonomous agent, pointed at the
# local LiteLLM basket (gpt-oss-120b over Groq/Cerebras/Cloudflare).
#
# Runs in CONTAINER mode: a persistent writable Ubuntu layer so the agent can
# apt/pip/npm install and self-modify. The upstream module runs the container
# with --network=host, so 127.0.0.1:<litellm> reaches the local proxy directly.
#
# Pairs with myNixOS.services.litellm on the same host (see the assertion).
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
    litellmPort = config.port-selector.ports.litellm;
  in {
    imports = [ inputs.hermes-agent.nixosModules.default ];

    options.myNixOS.services.hermes-agent = {
      enable = lib.mkEnableOption "myNixOS.services.hermes-agent";
      discord.enable = lib.mkEnableOption ''
        Hermes Discord integration. Needs op://Homelab/Hermes-Discord/envFile
        containing DISCORD_BOT_TOKEN'';
    };

    config = lib.mkIf cfg.enable {
      assertions = [{
        assertion = config.myNixOS.services.litellm.enable;
        message = ''
          myNixOS.services.hermes-agent expects myNixOS.services.litellm enabled
          on the same host — it points at the local LiteLLM endpoint.
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

        settings.model = {
          default = "gpt-oss-120b";
          provider = "custom";   # any OpenAI-compatible endpoint
          base_url = "http://127.0.0.1:${toString litellmPort}/v1";
          # LiteLLM runs without auth; the OpenAI client still wants a non-empty
          # key. This is a placeholder, not a secret.
          api_key = "sk-litellm-noauth";
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
    };
  };
}
