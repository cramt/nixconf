{ ... }: {
  hmModules.features.codex = { config, lib, pkgs, ... }: {
    options.myHomeManager.codex.enable = lib.mkEnableOption "myHomeManager.codex";
    config = lib.mkIf config.myHomeManager.codex.enable {
      programs.codex = {
        enable = true;
        settings = {
          model = "qwen3.6-27b";
          model_provider = "llama-cpp";
          model_providers = {
            llama-cpp = { name = "llama.cpp"; baseURL = "http://localhost:11434/v1"; };
          };
          # Enable Codex's hook system so herdr's SessionStart agent-state hook
          # (installed by `herdr integration install codex`) actually fires.
          # herdr can't set this itself — config.toml is a read-only HM symlink.
          features.hooks = true;
        };
      };
    };
  };
}
