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

      plugin = [
        "opencode-antigravity-auth@beta"
        "opencode-anthropic-auth@0.0.8"
      ];

      provider = {
        anthropic = {
          name = "Anthropic";
          options = {
            baseURL = "https://api.anthropic.com/v1";
          };
        };
        google = {
          npm = "@ai-sdk/google";
          models = {
            "antigravity-gemini-3-pro-low" = {
              name = "Gemini 3 Pro Low (Antigravity)";
              limit = {
                context = 1048576;
                output = 65535;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
            "antigravity-gemini-3-pro-high" = {
              name = "Gemini 3 Pro High (Antigravity)";
              limit = {
                context = 1048576;
                output = 65535;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };

            "antigravity-gemini-3-flash" = {
              name = "Gemini 3 Flash (Antigravity)";
              limit = {
                context = 1048576;
                output = 65536;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };

            "antigravity-claude-sonnet-4-5" = {
              name = "Claude Sonnet 4.5 (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };

            "antigravity-claude-sonnet-4-5-thinking-low" = {
              name = "Claude Sonnet 4.5 Thinking Low (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
            "antigravity-claude-sonnet-4-5-thinking-medium" = {
              name = "Claude Sonnet 4.5 Thinking Medium (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
            "antigravity-claude-sonnet-4-5-thinking-high" = {
              name = "Claude Sonnet 4.5 Thinking High (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };

            "antigravity-claude-opus-4-5-thinking-low" = {
              name = "Claude Opus 4.5 Thinking Low (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
            "antigravity-claude-opus-4-5-thinking-medium" = {
              name = "Claude Opus 4.5 Thinking Medium (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
            "antigravity-claude-opus-4-5-thinking-high" = {
              name = "Claude Opus 4.5 Thinking High (Antigravity)";
              limit = {
                context = 200000;
                output = 64000;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };

            "antigravity-gpt-oss-120b-medium" = {
              name = "GPT-OSS 120B Medium (Antigravity)";
              limit = {
                context = 131072;
                output = 32768;
              };
              modalities = {
                input = ["text" "image" "pdf"];
                output = ["text"];
              };
            };
          };
        };

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
