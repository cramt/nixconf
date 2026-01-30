{
  config,
  pkgs,
  inputs,
  ...
}: let
  secrets = import ../../secrets.nix;
in {
  programs.opencode = {
    enable = true;
    package = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

    settings = {
      autoshare = false;
      autoupdate = false;

      # Default model: Claude Sonnet 4.5 via Max subscription (best for agentic coding)
      model = "anthropic/claude-sonnet-4-5";
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
          description = "Full development agent with Claude Sonnet 4.5 (Max)";
          mode = "primary";
          model = "anthropic/claude-sonnet-4-5";
          temperature = 0.3;
        };

        # Planning/analysis agent - Gemini via Antigravity (FREE)
        # Best for: read-only analysis, planning, code review without changes
        # Use this to preserve Claude Max quota
        plan = {
          description = "Read-only analysis with Gemini 3 Pro (Antigravity - free)";
          mode = "primary";
          model = "google/antigravity-gemini-3-pro-low";
          temperature = 0.1;
          permission = {
            edit = "deny";
            write = "deny";
            bash = "ask";
          };
        };

        # Deep reasoning agent - Claude Opus via Max
        # Best for: complex architecture, difficult bugs, critical decisions
        # Use sparingly - highest quota consumption
        deep = {
          description = "Complex reasoning with Claude Opus 4.5 (Max)";
          mode = "primary";
          model = "anthropic/claude-opus-4-5";
          temperature = 0.2;
        };

        # SUBAGENTS (invoke with @mention)

        # Fast exploration - Gemini Flash via Antigravity (FREE)
        # Best for: codebase exploration, finding files, quick searches
        explore = {
          description = "Fast codebase exploration with Gemini Flash (free)";
          mode = "subagent";
          model = "google/antigravity-gemini-3-flash";
          temperature = 0.1;
          maxSteps = 10;
          tools = {
            write = false;
            edit = false;
          };
        };

        # Quick fixes - Gemini Flash via Antigravity (FREE)
        # Best for: simple fixes, small changes, rapid iteration
        quick = {
          description = "Quick fixes with Gemini Flash (free)";
          mode = "subagent";
          model = "google/antigravity-gemini-3-flash";
          temperature = 0.3;
          maxSteps = 5;
        };

        # Code review - Claude Sonnet via Max
        # Best for: thorough code review, security analysis
        review = {
          description = "Code review with Claude Sonnet (Max)";
          mode = "subagent";
          model = "anthropic/claude-sonnet-4-5";
          temperature = 0.1;
          tools = {
            write = false;
            edit = false;
            bash = false;
          };
        };

        # Documentation - Gemini Pro via Antigravity (FREE)
        # Best for: writing docs, README files, comments
        # Uses Gemini's 1M context for large codebase understanding
        docs = {
          description = "Documentation writing with Gemini Pro (free)";
          mode = "subagent";
          model = "google/antigravity-gemini-3-pro-high";
          temperature = 0.4;
          tools = {
            bash = false;
          };
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

        google = {
          models = {
            antigravity-gemini-3-pro = {
              name = "Gemini 3 Pro (Antigravity)";
              limit = {
                context = 1048576;
                output = 65535;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "pdf"
                ];
                output = [
                  "text"
                ];
              };
              variants = {
                low = {
                  thinkingLevel = "low";
                };
                high = {
                  thinkingLevel = "high";
                };
              };
            };
            antigravity-gemini-3-flash = {
              name = "Gemini 3 Flash (Antigravity)";
              limit = {
                context = 1048576;
                output = 65536;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "pdf"
                ];
                output = [
                  "text"
                ];
              };
              variants = {
                minimal = {
                  thinkingLevel = "minimal";
                };
                low = {
                  thinkingLevel = "low";
                };
                medium = {
                  thinkingLevel = "medium";
                };
                high = {
                  thinkingLevel = "high";
                };
              };
            };
            antigravity-claude-sonnet-4-5 = {
              name = "Claude Sonnet 4.5 (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "pdf"
                ];
                output = [
                  "text"
                ];
              };
            };
            antigravity-claude-sonnet-4-5-thinking = {
              name = "Claude Sonnet 4.5 Thinking (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "pdf"
                ];
                output = [
                  "text"
                ];
              };
              variants = {
                low = {
                  thinkingConfig = {
                    thinkingBudget = 8192;
                  };
                };
                max = {
                  thinkingConfig = {
                    thinkingBudget = 32768;
                  };
                };
              };
            };
            antigravity-claude-opus-4-5-thinking = {
              name = "Claude Opus 4.5 Thinking (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "pdf"
                ];
                output = [
                  "text"
                ];
              };
              variants = {
                low = {
                  thinkingConfig = {
                    thinkingBudget = 8192;
                  };
                };
                max = {
                  thinkingConfig = {
                    thinkingBudget = 32768;
                  };
                };
              };
            };
            "gemini-2.5-flash" = {
              name = "Gemini 2.5 Flash (Gemini CLI)";
              limit = {
                context = 1048576;
                output = 65536;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "pdf"
                ];
                output = [
                  "text"
                ];
              };
            };
            "gemini-2.5-pro" = {
              name = "Gemini 2.5 Pro (Gemini CLI)";
              limit = {
                context = 1048576;
                output = 65536;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "pdf"
                ];
                output = [
                  "text"
                ];
              };
            };
            gemini-3-flash-preview = {
              name = "Gemini 3 Flash Preview (Gemini CLI)";
              limit = {
                context = 1048576;
                output = 65536;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "pdf"
                ];
                output = [
                  "text"
                ];
              };
            };
            gemini-3-pro-preview = {
              name = "Gemini 3 Pro Preview (Gemini CLI)";
              limit = {
                context = 1048576;
                output = 65535;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "pdf"
                ];
                output = [
                  "text"
                ];
              };
            };
          };
        };

        # GitHub Copilot - kept as emergency fallback (only 50 requests/month on free tier)
        # Use sparingly or remove if not needed
        copilot = {
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
              name = "gptoss 20B";
            };
          };
        };
      };
    };
  };
}
