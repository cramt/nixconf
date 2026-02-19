{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.myNixOS.services.ollama;

  home = "/var/lib/ollama";
  models = "${home}/models";

  pkgFor = gpu: {
    rocm = pkgs.ollama-rocm;
    cuda = pkgs.ollama-cuda;
  }.${gpu};

  instanceList = lib.mapAttrsToList (name: icfg: {
    inherit name;
    inherit (icfg) gpu rocmVersion visibleDevices;
    pkg = pkgFor icfg.gpu;
    port = config.port-selector.ports."ollama-${name}";
  }) cfg.instances;

  mkOllamaService = {
    name,
    gpu,
    rocmVersion,
    visibleDevices,
    pkg,
    port,
  }: {
    description = "Ollama instance (${name})";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    environment =
      {
        HOME = home;
        OLLAMA_MODELS = models;
        OLLAMA_HOST = "0.0.0.0:${toString port}";
      }
      // lib.optionalAttrs (visibleDevices != null && gpu == "cuda") {
        CUDA_VISIBLE_DEVICES = visibleDevices;
      }
      // lib.optionalAttrs (visibleDevices != null && gpu == "rocm") {
        ROCR_VISIBLE_DEVICES = visibleDevices;
      }
      // lib.optionalAttrs (gpu == "rocm" && rocmVersion != "") {
        HSA_OVERRIDE_GFX_VERSION = rocmVersion;
      };
    serviceConfig = {
      Type = "exec";
      ExecStart = "${pkg}/bin/ollama serve";
      User = "ollama";
      Group = "ollama";
      WorkingDirectory = home;
      StateDirectory = ["ollama"];
      ReadWritePaths = [home models];
      PrivateDevices = false;
      DevicePolicy = "closed";
      DeviceAllow = [
        # CUDA
        "char-nvidiactl"
        "char-nvidia-caps"
        "char-nvidia-frontend"
        "char-nvidia-uvm"
        # ROCm
        "char-drm"
        "char-fb"
        "char-kfd"
        # WSL
        "/dev/dxg"
      ];
      SupplementaryGroups = ["render"];
      Restart = "always";
      RestartSec = "3";
    };
  };
in {
  options.myNixOS.services.ollama = {
    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["qwen3:8b"];
      description = "Models to pull on startup (via first instance)";
    };
    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          gpu = lib.mkOption {
            type = lib.types.enum ["rocm" "cuda"];
            description = "GPU backend for this instance";
          };
          rocmVersion = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "ROCm GFX version override (sets HSA_OVERRIDE_GFX_VERSION)";
          };
          visibleDevices = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Device selection: CUDA_VISIBLE_DEVICES for cuda, ROCR_VISIBLE_DEVICES for rocm (null = all devices)";
          };
          port = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
            description = "Fixed port for this instance (null = auto-assign via port-selector)";
          };
        };
      });
      default = {};
      description = "Named ollama instances, each binding to its own port";
    };
  };

  config = {
    port-selector.auto-assign = lib.mapAttrsToList (name: _: "ollama-${name}") (
      lib.filterAttrs (_: icfg: icfg.port == null) cfg.instances
    );
    port-selector.set-ports = lib.mapAttrs' (name: icfg:
      lib.nameValuePair (toString icfg.port) "ollama-${name}"
    ) (lib.filterAttrs (_: icfg: icfg.port != null) cfg.instances);

    networking.firewall.allowedTCPPorts = map ({port, ...}: port) instanceList;

    users.users.ollama = {
      isSystemUser = true;
      group = "ollama";
      inherit home;
    };
    users.groups.ollama = {};

    environment.systemPackages = lib.unique (map ({pkg, ...}: pkg) instanceList);

    systemd.services =
      lib.listToAttrs (
        map (inst: lib.nameValuePair "ollama-${inst.name}" (mkOllamaService inst))
        instanceList
      )
      // lib.optionalAttrs (cfg.loadModels != [] && instanceList != []) (let
        firstInst = lib.head instanceList;
      in {
        ollama-model-loader = {
          description = "Download ollama models";
          wantedBy = ["multi-user.target" "ollama-${firstInst.name}.service"];
          wants = ["network-online.target"];
          after = ["ollama-${firstInst.name}.service" "network-online.target"];
          bindsTo = ["ollama-${firstInst.name}.service"];
          environment = {
            HOME = home;
            OLLAMA_MODELS = models;
            OLLAMA_HOST = "127.0.0.1:${toString firstInst.port}";
          };
          serviceConfig = {
            Type = "exec";
            User = "ollama";
            Restart = "on-failure";
            RestartSec = "1s";
            RestartMaxDelaySec = "2h";
            RestartSteps = "10";
            ExecStart = pkgs.writeShellScript "ollama-model-loader" ''
              ${pkgs.parallel}/bin/parallel --tag ${firstInst.pkg}/bin/ollama pull \
                ::: ${lib.escapeShellArgs cfg.loadModels}
            '';
          };
        };
      });
  };
}
