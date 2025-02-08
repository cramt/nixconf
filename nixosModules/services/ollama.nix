{...}: {
  services.ollama = {
    enable = true;
    loadModels = [
      "deepseek-v3"
    ];
    acceleration = "rocm";
  };
}
