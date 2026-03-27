{ inputs, ... }: {
  hmModules.features.opencode = { config, lib, pkgs, ... }: {
    options.myHomeManager.opencode.enable = lib.mkEnableOption "myHomeManager.opencode";
    config = lib.mkIf config.myHomeManager.opencode.enable {
      programs.zsh.initContent = ''
        [[ -f /var/lib/opnix/secrets/ollamaBearerEnv ]] && { set -a; source /var/lib/opnix/secrets/ollamaBearerEnv; set +a; }
      '';

      home.sessionVariables.CHROMIUM_PATH = "${pkgs.chromium}/bin/chromium";

      programs.opencode = {
        enable = true;
        package = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

        settings = {
          autoshare = false;
          autoupdate = false;

          model = "anthropic/claude-sonnet-4-6";
          small_model = "anthropic/claude-haiku-4-5";
          default_agent = "build";

          compaction = {
            auto = true;
            prune = true;
          };

          plugin = [
            "opencode-antigravity-auth@latest"
            "opencode-anthropic-auth@latest"
            "opencode-m365-auth@latest"
          ];

          agent = {
            build = {
              description = "Full development agent with Claude Sonnet 4.6 (Max)";
              mode = "primary";
              model = "anthropic/claude-sonnet-4-6";
              temperature = 0.3;
            };
            deep = {
              description = "Complex reasoning with Claude Opus 4.6 (Max)";
              mode = "primary";
              model = "anthropic/claude-opus-4-6";
              temperature = 0.2;
            };
            explore = {
              description = "Fast codebase exploration with Gemini 3 Flash (free)";
              mode = "subagent";
              model = "google/gemini-3-flash-preview";
              temperature = 0.1;
              maxSteps = 10;
              permission = {
                write = "deny";
                edit = "deny";
              };
            };
            quick = {
              description = "Quick fixes with Gemini 3 Flash (free)";
              mode = "subagent";
              model = "google/gemini-3-flash-preview";
              temperature = 0.3;
              maxSteps = 5;
            };
            review = {
              description = "Code review with Claude Sonnet 4.6 (Max)";
              mode = "subagent";
              model = "anthropic/claude-sonnet-4-6";
              temperature = 0.1;
              permission = {
                write = "deny";
                edit = "deny";
                bash = "deny";
              };
            };
            docs = {
              description = "Documentation writing with Gemini 3.1 Pro (free)";
              mode = "subagent";
              model = "google/gemini-3.1-pro-preview";
              temperature = 0.4;
              permission = {
                bash = "deny";
              };
            };
            local = {
              description = "Local reasoning with DeepSeek R1 32B";
              mode = "subagent";
              model = "ollama/deepseek-r1:32b";
              temperature = 0.2;
            };
          };

          provider = {
            anthropic = {
              name = "Anthropic (Claude Max)";
              options = {
                baseURL = "https://api.anthropic.com/v1";
                timeout = 600000;
              };
            };
            m365 = {
              npm = "@ai-sdk/openai-compatible";
              name = "M365 Copilot";
              models = {
                "m365-copilot" = { name = "M365 Copilot (Auto)"; };
                "gpt-5.4" = { name = "GPT-5.4 Think Deeper"; };
                "gpt-5.4-quick" = { name = "GPT-5.4 Quick"; };
                "gpt-5.3" = { name = "GPT-5.3 Quick"; };
                "gpt-5.3-think-deeper" = { name = "GPT-5.3 Think Deeper"; };
                "gpt-5.2" = { name = "GPT-5.2 Quick"; };
                "gpt-5.2-think-deeper" = { name = "GPT-5.2 Think Deeper"; };
              };
            };
            ollama = {
              npm = "@ai-sdk/openai-compatible";
              name = "Ollama";
              options = {
                baseURL = "https://ollama.cramt.dk/olla/openai/v1";
                headers = {
                  Authorization = "Bearer {env:OLLAMA_BEARER_SECRET}";
                };
              };
              models = {
                "qwen3-coder:32b" = { name = "Qwen3-Coder 32B"; };
                "gpt-oss:20b" = { name = "GPT-OSS 20B"; };
                "deepseek-r1:32b" = { name = "DeepSeek R1 32B"; };
                "codestral:22b" = { name = "Codestral 22B"; };
                "devstral" = { name = "Devstral"; };
                "llama3.3:70b" = { name = "Llama 3.3 70B"; };
                "phi4:14b" = { name = "Phi-4 14B"; };
              };
            };
          };
        };
      };
    };
  };
}
