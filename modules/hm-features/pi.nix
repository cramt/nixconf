{inputs, ...}: {
  hmModules.features.pi = {
    config,
    lib,
    osConfig,
    ...
  }: let
    cfg = config.myHomeManager.pi;

    # The proxy (when enabled on this host) registers itself with port-selector;
    # read the same assigned port so pi and the service always agree.
    m365Enabled = osConfig.myNixOS.services.m365-copilot-proxy.enable or false;
    m365Port = osConfig.port-selector.ports.m365-copilot-proxy or null;
    m365ModelsJson = builtins.toJSON {
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
    };
  in {
    imports = [inputs.pi.homeModules.default];

    options.myHomeManager.pi.enable = lib.mkEnableOption "myHomeManager.pi";

    config = lib.mkIf cfg.enable {
      programs.pi.coding-agent = {
        enable = true;

        # ~/.pi/agent/settings.json. pi mutates this file at runtime (e.g.
        # lastChangelogVersion), so the module jq-merges our declared values
        # over it on every launch — declared keys stay authoritative. When the
        # M365 proxy is enabled on this host it's the default provider/model;
        # otherwise pi falls back to anthropic.
        settings = {
          defaultProvider = "anthropic";
          defaultModel = "claude-sonnet-4-6";
          defaultThinkingLevel = "medium";

          compaction.enabled = true;

          enableInstallTelemetry = false;
        } // lib.optionalAttrs m365Enabled {
          defaultProvider = "m365";
          defaultModel = "m365-copilot";
        };

        # NB: we deliberately do NOT set the module's `models` option — its
        # runtime installer writes ~/.pi/agent/models.json as a *mutable real
        # file* that never updates on rebuild (it only refreshes a symlink).
        # models.json is pure read-only config, so home-manager owns it below
        # as a store symlink → fully declarative, refreshes every switch.
      };

      # Register the local M365 Copilot proxy as a provider, declaratively.
      # Use it with the default model, or `pi --provider anthropic` for a one-off.
      # Keep the toolset lean (M365 disengages on large tool payloads), e.g.
      # `pi --tools read,list,edit,write`.
      home.file.".pi/agent/models.json" = lib.mkIf m365Enabled {
        text = m365ModelsJson;
      };
    };
  };
}
