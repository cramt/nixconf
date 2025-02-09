{...}: {
  services.ollama = {
    enable = true;
    loadModels = [
      "mistral"
    ];
    acceleration = "rocm";
    environmentVariables = {
      HCC_AMDGPU_TARGET = "gfx1101";
    };
    rocmOverrideGfx = "11.0.1";
  };
}
