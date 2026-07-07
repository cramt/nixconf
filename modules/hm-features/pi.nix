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
        # All slugs the proxy maps to an M365 tone (see MODEL_TONES in
        # @m365-copilot/core). m365-copilot is the default "magic" auto-router;
        # the gpt-5.x slugs pin a specific backend tone. NB: "-think-deeper" and
        # the bare gpt-5.4 slug resolve to the same reasoning tone — the
        # reasoning tiers tend to batch tool calls, the default is the most
        # disciplined at one-call-per-turn. Switch with `pi --model <id>`.
        # Every slug the proxy maps to an M365 tone (mirrors MODEL_TONES /
        # getAvailableModels in @m365-copilot/core). Switch with `pi --model <id>`.
        models = [
          # Claude tones route AGENT-LESS (the /claude/ path) and tool-call well in
          # practice; use Claude Code for Anthropic models normally, these are here
          # as a fallback.
          { id = "claude-sonnet"; name = "Claude Sonnet 4.5 (agent-less)"; }
          { id = "claude-sonnet-4.5"; name = "Claude Sonnet 4.5 (alias)"; }
          { id = "claude"; name = "Claude (-> Sonnet 4.5)"; }
          { id = "claude-sonnet-think-deeper"; name = "Claude Sonnet Reasoning (agent-less)"; }
          { id = "claude-opus"; name = "Claude Opus (agent-less, experimental)"; }

          # GPT tones run WITH the tool agent. Prefer these explicit tones over the
          # `magic` auto-router, which is high-variance at turn-1 tool-calling
          # (hypotheses F24). gpt-5.5-think-deeper is the default and works well.
          { id = "gpt-5.5"; name = "GPT-5.5 (chat)"; }
          { id = "gpt-5.5-quick"; name = "GPT-5.5 Quick"; }
          { id = "gpt-5.5-think-deeper"; name = "GPT-5.5 Think Deeper (reasoning)"; }
          { id = "gpt-5.4"; name = "GPT-5.4 (reasoning)"; }
          { id = "gpt-5.4-think-deeper"; name = "GPT-5.4 Think Deeper (reasoning)"; }
          { id = "gpt-5.4-quick"; name = "GPT-5.4 Quick"; }
          { id = "gpt-5.3"; name = "GPT-5.3 Quick"; }
          { id = "gpt-5.3-quick"; name = "GPT-5.3 Quick"; }
          { id = "gpt-5.3-think-deeper"; name = "GPT-5.3 Think Deeper (reasoning)"; }
          { id = "gpt-5.2"; name = "GPT-5.2 Quick"; }
          { id = "gpt-5.2-quick"; name = "GPT-5.2 Quick"; }
          { id = "gpt-5.2-think-deeper"; name = "GPT-5.2 Think Deeper (reasoning)"; }
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
          # Explicit GPT reasoning tone (works well in real sessions) rather than
          # the high-variance `magic` auto-router. Claude models are in the list too
          # but Claude Code is the normal path for those.
          defaultModel = "gpt-5.5-think-deeper";
        };

        # NB: we deliberately do NOT set the module's `models` option — its
        # runtime installer writes ~/.pi/agent/models.json as a *mutable real
        # file* that never updates on rebuild (it only refreshes a symlink).
        # models.json is pure read-only config, so home-manager owns it below
        # as a store symlink → fully declarative, refreshes every switch.
      };

      # pi's GLOBAL instruction file (loaded first, before any project AGENTS.md).
      # Same source as the Claude Code global CLAUDE.md so pi knows the machine is
      # NixOS, how to install packages, git/clipboard conventions, etc. Not gated on
      # the proxy — the guidance applies to every pi session.
      home.file.".pi/agent/AGENTS.md".source = ./global-agent-instructions.md;

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
