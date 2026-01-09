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
