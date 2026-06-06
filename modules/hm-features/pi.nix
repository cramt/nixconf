{inputs, ...}: {
  hmModules.features.pi = {
    config,
    lib,
    ...
  }: {
    imports = [inputs.pi.homeModules.default];

    options.myHomeManager.pi.enable = lib.mkEnableOption "myHomeManager.pi";

    config = lib.mkIf config.myHomeManager.pi.enable {
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
      };
    };
  };
}
