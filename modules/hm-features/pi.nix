{inputs, ...}: {
  hmModules.features.pi = {
    config,
    lib,
    pkgs,
    osConfig,
    ...
  }: let
    cfg = config.myHomeManager.pi;

    # The proxy (when enabled on this host) registers itself with port-selector;
    # read the same assigned port so pi and the service always agree.
    m365Enabled = osConfig.myNixOS.services.m365-copilot-proxy.enable or false;
    m365Port = osConfig.port-selector.ports.m365-copilot-proxy or null;
    m365Models = pkgs.writeText "pi-models.json" (builtins.toJSON {
      providers.m365 = {
        baseUrl = "http://localhost:${toString m365Port}/v1";
        api = "openai-completions";
        apiKey = "m365";
        compat = {
          supportsDeveloperRole = false;
          supportsReasoningEffort = false;
          supportsUsageInStreaming = false;
        };
        models = [
          {
            id = "m365-copilot";
            name = "M365 Copilot";
          }
        ];
      };
    });
  in {
    imports = [inputs.pi.homeModules.default];

    options.myHomeManager.pi.enable = lib.mkEnableOption "myHomeManager.pi";

    config = lib.mkIf cfg.enable {
      programs.pi.coding-agent = {
        enable = true;

        # ~/.pi/agent/settings.json
        settings = {
          defaultProvider = "anthropic";
          defaultModel = "claude-sonnet-4-6";
          defaultThinkingLevel = "medium";

          compaction.enabled = true;

          enableInstallTelemetry = false;
        };

        # Register the local M365 Copilot proxy as a provider when it's enabled
        # on this host (→ ~/.pi/agent/models.json). Use it with
        # `pi --models "m365*"` or `pi --provider m365 --model m365-copilot`.
        # Keep the toolset lean (M365 disengages on large tool payloads), e.g.
        # `pi --models "m365*" --tools read,list,edit,write`.
        models = lib.mkIf m365Enabled m365Models;
      };
    };
  };
}
