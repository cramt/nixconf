# OpenAI-compatible proxy fronting the Claude Agent SDK with caller-side
# tool-call passthrough. Lets Hermes (or any OpenAI client) use Claude as its
# brain while billing the Claude *subscription* rather than a metered API key.
#
# Before enabling on a host:
#
#   1. On a machine logged into your Claude (Max) subscription, run:
#        claude setup-token
#      and store the resulting `sk-ant-oat...` token in 1Password as
#        op://Homelab/ClaudeSubscription/envFile
#      with one dotenv line:
#        CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat...
#      (Alternatively drop an ANTHROPIC_API_KEY=… line and set
#      `allowApiKey = true` below for metered pay-per-token instead.)
#
#   2. Set `myNixOS.services.claude-sub-proxy.enable = true;` on the host
#      (the host must also have `myNixOS.opnix-secrets.enable = true;`).
#
# The port is assigned through the repo's port-selector; the hermes-agent
# module reads the same value via config.port-selector.ports.claude-sub-proxy.
{ inputs, ... }: {
  flake.nixosModules."services.claude-sub-proxy" = { config, lib, ... }:
  let
    cfg = config.myNixOS.services.claude-sub-proxy;
  in {
    imports = [ inputs.claude-sub-proxy.nixosModules.default ];

    options.myNixOS.services.claude-sub-proxy = {
      enable = lib.mkEnableOption "myNixOS.services.claude-sub-proxy";
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Address to bind. Defaults to localhost — the proxy is unauthenticated
          and drives a paid Claude subscription, so don't expose it to untrusted
          networks.
        '';
      };
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the proxy port in the firewall.";
      };
      defaultModel = lib.mkOption {
        type = lib.types.str;
        default = "claude-opus-4-8";
        description = "Model used when a request does not specify one.";
      };
      allowApiKey = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          By default the proxy strips ANTHROPIC_API_KEY so the Agent SDK bills
          your subscription. Set true to allow a metered ANTHROPIC_API_KEY
          (pay-per-token) supplied via the opnix env file instead.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      port-selector.auto-assign = [ "claude-sub-proxy" ];

      services.claude-sub-proxy = {
        enable = true;
        inherit (cfg) host openFirewall defaultModel allowApiKey;
        port = config.port-selector.ports.claude-sub-proxy;
        environmentFiles = [
          config.services.onepassword-secrets.secretPaths.claudeSubProxyEnv
        ];
      };

      # opnix secret co-located with the service so it's only fetched on hosts
      # where the proxy is actually enabled.
      services.onepassword-secrets.secrets.claudeSubProxyEnv = {
        reference = "op://Homelab/ClaudeSubscription/envFile";
        services = [ "claude-sub-proxy" ];
      };
    };
  };
}
