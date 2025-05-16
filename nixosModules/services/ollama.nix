{
  lib,
  config,
  ...
}: let
  cfg = config.myNixOS.services.ollama;
in {
  options.myNixOS.services.ollama = {
    gpu = lib.mkOption {
      type = lib.types.enum ["rocm" "cuda"];
      description = ''
        which gpu
      '';
    };
    rocmVersion = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        which rocm version
      '';
    };
  };
  config = {
    networking.firewall.allowedTCPPorts = [11434];
    services.ollama = {
      enable = true;
      loadModels = [
        "mistral"
        "qwen2.5-coder:7b"
        "qwen2.5-coder:3b"
      ];
      host = "0.0.0.0";
      acceleration = cfg.gpu;
      environmentVariables = {
        HCC_AMDGPU_TARGET = lib.mkIf (cfg.rocmVersion != "") "gfx${builtins.replaceStrings ["."] [""] cfg.rocmVersion}";
      };
      rocmOverrideGfx = lib.mkIf (cfg.rocmVersion != "") cfg.rocmVersion;
    };
  };
}
