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
      default = null;
      description = ''
        which rocm version
      '';
    };
  };
  config = {
    services.ollama = {
      enable = true;
      loadModels = [
        "mistral"
      ];
      acceleration = cfg.gpu;
      environmentVariables = {
        HCC_AMDGPU_TARGET = lib.mkIf (cfg.rocmVersion != null) "gfx${builtins.replaceStrings ["."] [""] cfg.rocmVersion}";
      };
      rocmOverrideGfx = lib.mkIf (cfg.rocmVersion != null) cfg.rocmVersion;
    };
  };
}
