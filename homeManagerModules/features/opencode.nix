{...}: {
  programs.opencode = {
    enable = true;
    settings = {
      autoshare = false;
      autoupdate = false;
      provider = {
        ollama = {
          npm = "@ai-sdk/openai-compatible";
          name = "Ollama (local)";
          options.baseURL = "http://localhost:11434/v1";
          models = {
            "gpt-oss:20b".name = "gptoss";
          };
        };
      };
    };
  };
}
