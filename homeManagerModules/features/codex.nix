{...}: {
  programs.codex = {
    enable = true;
    settings = {
      model = "gpt-oss:20b";
      model_provider = "ollama";
      model_providers = {
        ollama = {
          name = "ollama";
          baseURL = "http://localhost:11434/v1";
        };
      };
    };
  };
}
