{ ... }: {
  flake.nixosModules."services.llama-cpp-rpc" = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.myNixOS.services.llama-cpp-rpc;

    pkgFor = gpu:
      {
        rocm = pkgs.llama-cpp.override {
          rocmSupport = true;
          rpcSupport = true;
        };
        cuda = pkgs.llama-cpp.override {
          cudaSupport = true;
          rpcSupport = true;
        };
      }
      .${gpu};

    pkg = pkgFor cfg.gpu;
    port =
      if cfg.port != null
      then cfg.port
      else config.port-selector.ports."llama-cpp-rpc";
  in {
    options.myNixOS.services.llama-cpp-rpc = {
      enable = lib.mkEnableOption "myNixOS.services.llama-cpp-rpc";

      gpu = lib.mkOption {
        type = lib.types.enum ["rocm" "cuda"];
        description = "GPU backend for the RPC worker";
      };

      rocmVersion = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "ROCm GFX version override (sets HSA_OVERRIDE_GFX_VERSION)";
      };

      visibleDevices = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Device selection: CUDA_VISIBLE_DEVICES for cuda, ROCR_VISIBLE_DEVICES for rocm (null = all)";
      };

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "Port for the RPC server (null = auto-assign via port-selector)";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Bind address for the RPC server";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra arguments passed to llama-rpc-server (e.g. [\"-c\"] for local tensor cache)";
      };
    };

    config = lib.mkIf cfg.enable {
      port-selector.auto-assign = lib.optional (cfg.port == null) "llama-cpp-rpc";
      port-selector.set-ports = lib.optionalAttrs (cfg.port != null) {
        "${toString cfg.port}" = "llama-cpp-rpc";
      };

      networking.firewall.allowedTCPPorts = [port];

      users.users.llama-cpp-rpc = {
        isSystemUser = true;
        group = "llama-cpp-rpc";
      };
      users.groups.llama-cpp-rpc = {};

      environment.systemPackages = [pkg];

      systemd.services.llama-cpp-rpc = {
        description = "llama.cpp RPC worker";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        environment =
          lib.optionalAttrs (cfg.visibleDevices != null && cfg.gpu == "cuda") {
            CUDA_VISIBLE_DEVICES = cfg.visibleDevices;
          }
          // lib.optionalAttrs (cfg.visibleDevices != null && cfg.gpu == "rocm") {
            ROCR_VISIBLE_DEVICES = cfg.visibleDevices;
          }
          // lib.optionalAttrs (cfg.gpu == "rocm" && cfg.rocmVersion != "") {
            HSA_OVERRIDE_GFX_VERSION = cfg.rocmVersion;
          };
        serviceConfig = {
          Type = "exec";
          ExecStart = lib.concatStringsSep " " ([
              "${pkg}/bin/llama-rpc-server"
              "-H"
              cfg.host
              "-p"
              (toString port)
            ]
            ++ cfg.extraArgs);
          User = "llama-cpp-rpc";
          Group = "llama-cpp-rpc";
          PrivateDevices = false;
          DevicePolicy = "closed";
          DeviceAllow = [
            "char-nvidiactl"
            "char-nvidia-caps"
            "char-nvidia-frontend"
            "char-nvidia-uvm"
            "char-drm"
            "char-fb"
            "char-kfd"
            "/dev/dxg"
          ];
          SupplementaryGroups = ["render" "video"];
          Restart = "always";
          RestartSec = "3";
        };
      };
    };
  };
}
