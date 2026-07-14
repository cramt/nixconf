# LiteLLM proxy — one OpenAI-compatible endpoint fronting a basket of free
# inference providers (Groq, Cerebras, Cloudflare Workers AI).
#
# All three deployments serve the SAME underlying model (gpt-oss-120b) under a
# single `model_name`, so a client (e.g. OpenClaw) always asks for one model and
# always gets that model — only the provider underneath changes when one tier
# rate-limits or runs out. Routing shuffles across the three (spreading usage so
# each free tier lasts longer) and cools a backend down for 60s on a 429.
#
# Credentials live in three 1Password items in the Homelab vault, each with an
# `envFile` field holding dotenv lines:
#   op://Homelab/GROQ/envFile          -> GROQ_API_KEY=gsk_...
#   op://Homelab/Cerebras/envFile      -> CEREBRAS_API_KEY=csk-...
#   op://Homelab/Cloudflare AI/envFile -> CLOUDFLARE_API_KEY=...
#                                          CLOUDFLARE_API_BASE=https://api.cloudflare.com/client/v4/accounts/<id>/ai/v1
# opnix renders each to its own file and systemd loads all three as
# EnvironmentFiles (it merges them), so the provider keys stay out of the store.
#
# To enable on a host, set `myNixOS.services.litellm.enable = true;`
# (the host must also have `myNixOS.opnix-secrets.enable = true;`).
#
# The port is assigned through the repo's port-selector. Bind stays on
# 127.0.0.1 by default — the proxy is unauthenticated and holds provider keys,
# so don't expose it to untrusted networks.
{ ... }: {
  flake.nixosModules."services.litellm" = { config, lib, ... }:
  let
    cfg = config.myNixOS.services.litellm;
    port = config.port-selector.ports.litellm;

    # One logical model, three backends. Keep these ids in sync if a provider
    # renames the model — they must all resolve to gpt-oss-120b so behaviour is
    # identical across failover.
    modelName = "gpt-oss-120b";
    deployment = model: {
      model_name = modelName;
      litellm_params = { inherit model; };
    };

    # When the local M365 Copilot proxy is enabled on this same host, front its
    # OpenAI-compatible endpoint through LiteLLM as well. LiteLLM exposes an
    # Anthropic `/v1/messages` bridge, which is the only dialect Claude Code
    # speaks — so this is what lets `claude-m365` drive Claude Code against the
    # M365 models. Slugs mirror the tone list documented in
    # modules/hm-features/pi.nix; Claude tones tool-call well, `quick` is a cheap
    # small/fast model for Claude Code's background calls.
    m365 = config.myNixOS.services.m365-copilot-proxy;
    m365Base = "http://127.0.0.1:${toString config.port-selector.ports.m365-copilot-proxy}/v1";
    m365Slugs = [ "claude-sonnet-4.5" "claude-opus" "gpt-5.5" "gpt-5.5-think-deeper" "quick" ];
    m365Deployment = slug: {
      model_name = slug;
      litellm_params = {
        model = "openai/${slug}";
        api_base = m365Base;
        # Proxy is unauthenticated, but LiteLLM's openai provider still requires
        # a non-empty key field.
        api_key = "dummy";
      };
    };
  in {
    options.myNixOS.services.litellm = {
      enable = lib.mkEnableOption "myNixOS.services.litellm";
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Address to bind. Defaults to localhost — the proxy is unauthenticated
          and holds free-tier provider keys, so don't expose it to untrusted
          networks.
        '';
      };
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the LiteLLM port in the firewall.";
      };
    };

    config = lib.mkIf cfg.enable {
      port-selector.auto-assign = [ "litellm" ];

      services.litellm = {
        enable = true;
        inherit (cfg) host openFirewall;
        inherit port;
        # The upstream module only takes a single environmentFile; the keys are
        # spread across three opnix items, so we hand systemd all three files
        # directly (mkForce) below instead.
        settings = {
          model_list = [
            # Groq & Cerebras: native LiteLLM providers read their key from env.
            (deployment "groq/openai/gpt-oss-120b")   # GROQ_API_KEY
            (deployment "cerebras/gpt-oss-120b")      # CEREBRAS_API_KEY
            # Cloudflare: LiteLLM's native `cloudflare/` provider uses the legacy
            # /ai/run API and returns empty completions for gpt-oss. Hit its
            # OpenAI-compatible /ai/v1 endpoint instead (api_base carries the
            # account id; both come from the env file).
            {
              model_name = modelName;
              litellm_params = {
                model = "openai/@cf/openai/gpt-oss-120b";
                api_base = "os.environ/CLOUDFLARE_API_BASE";
                api_key = "os.environ/CLOUDFLARE_API_KEY";
              };
            }
          ] ++ lib.optionals m365.enable (map m365Deployment m365Slugs);
          router_settings = {
            # Spread load across the three free tiers so no single one is drained
            # first; on a 429 the deployment is benched for cooldown_time and the
            # request retried against the others.
            routing_strategy = "simple-shuffle";
            num_retries = 3;
            allowed_fails = 1;
            cooldown_time = 60;
          };
          litellm_settings = {
            # Providers disagree on which sampling params they accept; silently
            # drop unsupported ones instead of erroring, so the same client
            # request works against whichever backend serves it.
            drop_params = true;
          };
        };
      };

      # opnix secrets co-located with the service so they're only fetched on
      # hosts where LiteLLM is actually enabled. systemd reads EnvironmentFiles
      # as root before dropping to the DynamicUser, so default (root) ownership
      # is fine. mkForce replaces the upstream module's single-file default.
      services.onepassword-secrets.secrets = {
        litellmGroqEnv = {
          reference = "op://Homelab/GROQ/envFile";
          services = [ "litellm" ];
        };
        litellmCerebrasEnv = {
          reference = "op://Homelab/Cerebras/envFile";
          services = [ "litellm" ];
        };
        litellmCloudflareEnv = {
          reference = "op://Homelab/Cloudflare AI/envFile";
          services = [ "litellm" ];
        };
      };

      systemd.services.litellm.serviceConfig.EnvironmentFile = lib.mkForce [
        config.services.onepassword-secrets.secretPaths.litellmGroqEnv
        config.services.onepassword-secrets.secretPaths.litellmCerebrasEnv
        config.services.onepassword-secrets.secretPaths.litellmCloudflareEnv
      ];
    };
  };
}
