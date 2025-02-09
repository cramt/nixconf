{...}: {
  services.ollama = {
    enable = true;
    loadModels = [
      "llama3.2"
    ];
    acceleration = "rocm";
  };
}
