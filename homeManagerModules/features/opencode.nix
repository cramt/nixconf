{
  config,
  pkgs,
  ...
}: let
  secrets = import ../../secrets.nix;
in {
  programs.opencode = {
    enable = true;

    settings = {
      autoshare = false;
      autoupdate = false;

      # Default models - updated to latest recommended models
      model = "anthropic/claude-opus-4-5-20251101";
      small_model = "anthropic/claude-haiku-4-5-20251001";

      # Multi-provider configuration
      provider = {
        # Anthropic Claude (subscription)
        anthropic = {
          npm = "@ai-sdk/anthropic";
          name = "Anthropic";
          options = {
            baseURL = "https://api.anthropic.com/v1";
          };
          models = {
            "claude-opus-4-5-20251101" = {
              name = "Claude Opus 4.5";
            };
            "claude-sonnet-4-5-20250929" = {
              name = "Claude Sonnet 4.5";
            };
            "claude-sonnet-4-20250514" = {
              name = "Claude Sonnet 4";
            };
            "claude-haiku-4-5-20251001" = {
              name = "Claude Haiku 4.5";
            };
          };
        };

        # Google Gemini (free tier)
        gemini = {
          npm = "@ai-sdk/google";
          name = "Google Gemini";
          options = {
            baseURL = "https://generativelanguage.googleapis.com/v1beta/openai/";
          };
          models = {
            "gemini-3-pro" = {
              name = "Gemini 3 Pro";
            };
            "gemini-2-0-flash" = {
              name = "Gemini 2.0 Flash";
            };
            "gemini-2-0-pro-exp-02-05" = {
              name = "Gemini 2.0 Pro";
            };
          };
        };

        # GitHub Copilot (authenticate via CLI)
        copilot = {
          npm = "@ai-sdk/github";
          name = "GitHub Copilot";
          models = {
            "gpt-5.2" = {
              name = "GPT-5.2";
            };
            "gpt-5.1-codex" = {
              name = "GPT-5.1 Codex";
            };
            "gpt-4o" = {
              name = "GPT-4o";
            };
            "claude-3-5-sonnet" = {
              name = "Claude 3.5 Sonnet";
            };
          };
        };

        # Local Ollama (keep existing)
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
