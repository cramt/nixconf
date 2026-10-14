# OpenAI-compatible proxy for Microsoft 365 Copilot.
#
# Before enabling on a host:
#
#   1. Create the 1Password item op://Homelab/M365Copilot with one field:
#        secretsJson - the JSON the proxy reads, e.g.:
#                        {"email":"you@corp.com","password":"...","mfaSecret":"..."}
#
#   2. Set `myNixOS.services.m365-copilot-proxy.enable = true;` on the host
#      (the host must also have `myNixOS.opnix-secrets.enable = true;`).
{ inputs, ... }: {
  flake.nixosModules."services.m365-copilot-proxy" = { config, lib, ... }:
  let
    cfg = config.myNixOS.services.m365-copilot-proxy;
  in {
    imports = [ inputs.m365-copilot-proxy.nixosModules.default ];

    options.myNixOS.services.m365-copilot-proxy = {
      enable = lib.mkEnableOption "myNixOS.services.m365-copilot-proxy";
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Address to bind. Defaults to localhost — the proxy is unauthenticated
          and fronts a paid M365 account, so don't expose it to untrusted networks.
        '';
      };
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the proxy port in the firewall.";
      };
      # The proxy's own list is a TS map (packages/core/src/copilot.ts), not
      # something nix can read, and cli-proxy-api needs models spelled out:
      # it never asks an openai-compatibility upstream for /v1/models. Copied
      # from the running proxy's /v1/models; re-copy when bumping the input.
      models = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "m365-copilot" "auto" "quick" "think-deeper"
          "claude" "claude-sonnet" "claude-sonnet-4.5" "claude-sonnet-4.6"
          "claude-sonnet-5" "claude-sonnet-5.5" "claude-sonnet-think-deeper"
          "claude-opus" "claude-opus-4.5" "claude-opus-5" "claude-opus-5.5"
          "gpt-5.2" "gpt-5.2-quick" "gpt-5.2-think-deeper"
          "gpt-5.3" "gpt-5.3-quick" "gpt-5.3-think-deeper"
          "gpt-5.4" "gpt-5.4-quick" "gpt-5.4-think-deeper"
          "gpt-5.5" "gpt-5.5-quick" "gpt-5.5-think-deeper"
          "gpt-5.6" "gpt-5.6-quick" "gpt-5.6-think-deeper"
          "gpt-6-sol" "gpt-6-think-deeper"
        ];
        description = "Model ids the proxy serves, for clients that need them declared.";
      };
    };

    config = lib.mkIf cfg.enable {
      port-selector.auto-assign = [ "m365-copilot-proxy" ];

      services.m365-copilot-proxy = {
        enable = true;
        inherit (cfg) host openFirewall;
        port = config.port-selector.ports.m365-copilot-proxy;
        secretsFile = config.services.onepassword-secrets.secretPaths.m365CopilotProxySecrets;
        # Full untruncated debug logging to
        # /var/lib/m365-copilot-proxy/.config/opencode-m365/debug.log,
        # so failed requests can be reverse engineered from complete payloads.
        environment.M365_TRACE = "1";
      };

      # opnix secret co-located with the service so it's only fetched on hosts
      # where the proxy is actually enabled.
      services.onepassword-secrets.secrets.m365CopilotProxySecrets = {
        reference = "op://Homelab/M365Copilot/secretsJson";
        services = [ "m365-copilot-proxy" ];
      };
    };
  };
}
