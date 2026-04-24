{...}: {
  hmModules.features.opencode = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.myHomeManager.opencode.enable = lib.mkEnableOption "myHomeManager.opencode";
    config = lib.mkIf config.myHomeManager.opencode.enable {
      home.sessionVariables.CHROMIUM_PATH = "${pkgs.chromium}/bin/chromium";

      programs.opencode = {
        enable = true;
        package = pkgs.opencode;

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
            #"opencode-m365-auth@latest"
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
              description = "Local coding agent with Qwen3.6 27B";
              mode = "subagent";
              model = "llama-cpp-local/qwen3.6-27b";
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
                "m365-copilot" = {name = "M365 Copilot (Auto)";};
                "gpt-5.4" = {name = "GPT-5.4 Think Deeper";};
                "gpt-5.4-quick" = {name = "GPT-5.4 Quick";};
                "gpt-5.3" = {name = "GPT-5.3 Quick";};
                "gpt-5.3-think-deeper" = {name = "GPT-5.3 Think Deeper";};
                "gpt-5.2" = {name = "GPT-5.2 Quick";};
                "gpt-5.2-think-deeper" = {name = "GPT-5.2 Think Deeper";};
              };
            };
            llama-cpp-local = {
              npm = "@ai-sdk/openai-compatible";
              name = "llama.cpp (Local)";
              options = {
                baseURL = "http://localhost:11434/v1";
              };
              models = {
                "qwen3.6-27b" = {name = "Qwen3.6 27B";};
              };
            };
          };
        };
      };
    };
  };
}
