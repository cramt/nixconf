{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  cfg = config.myNixOS.services.ollama;
  master_pkgs = import inputs.nixpkgs-master {
    system = pkgs.system;
    config = {
      allowUnfree = true;
    };
  };
  port = config.port-selector.ports.ollama;
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
    networking.firewall.allowedTCPPorts = [port];
    port-selector.set-ports."11434" = "ollama";
    services.ollama = {
      #package = master_pkgs.ollama;
      enable = true;
      loadModels = [
        "gpt-oss:20b"
      ];
      host = "0.0.0.0";
      acceleration = cfg.gpu;
      port = port;
      environmentVariables = {
        HCC_AMDGPU_TARGET = lib.mkIf (cfg.rocmVersion != "") "gfx${builtins.replaceStrings ["."] [""] cfg.rocmVersion}";
        OLLAMA_GPU_OVERHEAD = "3G";
      };
      rocmOverrideGfx = lib.mkIf (cfg.rocmVersion != "") cfg.rocmVersion;
    };
  };
}
