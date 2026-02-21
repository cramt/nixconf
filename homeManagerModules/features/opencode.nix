{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.opencode = {
    enable = true;
    package = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

    settings = {
      autoshare = false;
      autoupdate = false;

      # Default model: Claude Sonnet 4.6 via Max subscription (best for agentic coding)
      model = "anthropic/claude-sonnet-4-6";
      # Lightweight tasks (title generation, etc.) use Haiku to save quota
      small_model = "anthropic/claude-haiku-4-5";
      # Start with the build agent by default
      default_agent = "build";

      # Token efficiency settings
      compaction = {
        auto = true; # Auto-compact when context is full
        prune = true; # Remove old tool outputs to save tokens
      };

      plugin = [
        "opencode-antigravity-auth@latest"
        "opencode-anthropic-auth@latest"
      ];

      # Agent configuration - optimized for your subscriptions
      # Primary agents: switch with Tab key
      # Subagents: invoke with @mention
      agent = {
        # PRIMARY AGENTS (Tab to switch)

        # Default coding agent - Claude Sonnet via Max
        # Best for: standard development, bug fixes, feature implementation
        build = {
          description = "Full development agent with Claude Sonnet 4.6 (Max)";
          mode = "primary";
          model = "anthropic/claude-sonnet-4-6";
          temperature = 0.3;
        };

        # Deep reasoning agent - Claude Opus via Max
        # Best for: complex architecture, difficult bugs, critical decisions
        # Use sparingly - highest quota consumption
        deep = {
          description = "Complex reasoning with Claude Opus 4.6 (Max)";
          mode = "primary";
          model = "anthropic/claude-opus-4-6";
          temperature = 0.2;
        };

        # SUBAGENTS (invoke with @mention)

        # Fast exploration - Gemini Flash (FREE)
        # Best for: codebase exploration, finding files, quick searches
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

        # Quick fixes - Gemini Flash (FREE)
        # Best for: simple fixes, small changes, rapid iteration
        quick = {
          description = "Quick fixes with Gemini 3 Flash (free)";
          mode = "subagent";
          model = "google/gemini-3-flash-preview";
          temperature = 0.3;
          maxSteps = 5;
        };

        # Code review - Claude Sonnet via Max
        # Best for: thorough code review, security analysis
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

        # Documentation - Gemini Pro (FREE)
        # Best for: writing docs, README files, comments
        # Uses Gemini's large context for codebase understanding
        docs = {
          description = "Documentation writing with Gemini 3.1 Pro (free)";
          mode = "subagent";
          model = "google/gemini-3.1-pro-preview";
          temperature = 0.4;
          permission = {
            bash = "deny";
          };
        };

        # Local Reasoning - DeepSeek R1 via Ollama
        # Best for: offline tasks, free reasoning, privacy-sensitive code
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
            timeout = 600000; # 10 min timeout for complex tasks
          };
        };

        ollama = {
          npm = "@ai-sdk/openai-compatible";
          name = "Ollama (local)";
          options = {
            baseURL = "http://localhost:11434/v1";
          };
          models = {
            "qwen3-coder:32b" = {
              name = "Qwen3-Coder 32B";
            };
            "gpt-oss:20b" = {
              name = "GPT-OSS 20B";
            };
            "deepseek-r1:32b" = {
              name = "DeepSeek R1 32B";
            };
            "codestral:22b" = {
              name = "Codestral 22B";
            };
            "devstral" = {
              name = "Devstral";
            };
            "llama3.3:70b" = {
              name = "Llama 3.3 70B";
            };
            "phi4:14b" = {
              name = "Phi-4 14B";
            };
          };
        };
      };
    };
  };
}
