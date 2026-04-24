{ ... }: {
  flake.nixosModules."services.llama-cpp" = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.myNixOS.services.llama-cpp;
    home = "/var/lib/llama-cpp";
    modelsDir = "${home}/models";

    hfHub = pkgs.python3Packages.huggingface-hub;

    # On-disk path for a declared model, keyed by repo + file so two models
    # from the same repo don't clobber each other.
    modelPath = m: "${modelsDir}/${lib.replaceStrings ["/"] ["_"] m.repo}/${m.file}";

    pkgFor = gpu: {
      rocm = pkgs.llama-cpp.override { rocmSupport = true; };
      cuda = pkgs.llama-cpp.override { cudaSupport = true; };
    }.${gpu};

    instanceList = lib.mapAttrsToList (name: icfg: {
      inherit name;
      inherit (icfg) gpu rocmVersion visibleDevices;
      pkg = pkgFor icfg.gpu;
      port = config.port-selector.ports."llama-cpp-${name}";
    }) cfg.instances;

    mkSwapConfig = inst: let
      yamlFormat = pkgs.formats.yaml {};
      modelsMap = lib.listToAttrs (map (m:
        lib.nameValuePair m.name {
          cmd = lib.concatStringsSep " " ([
            "${inst.pkg}/bin/llama-server"
            "--model" (modelPath m)
            "--port" "\${PORT}"
            "--host" "127.0.0.1"
          ] ++ m.args);
          ttl = m.ttl;
        }
      ) cfg.models);
    in yamlFormat.generate "llama-swap-${inst.name}.yaml" {
      healthCheckTimeout = 600;
      logLevel = "info";
      models = modelsMap;
    };

    mkSwapService = inst: {
      description = "llama-swap instance (${inst.name})";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "llama-cpp-model-loader.service"];
      requires = lib.optional (cfg.models != []) "llama-cpp-model-loader.service";
      environment =
        lib.optionalAttrs (inst.visibleDevices != null && inst.gpu == "cuda") {
          CUDA_VISIBLE_DEVICES = inst.visibleDevices;
        }
        // lib.optionalAttrs (inst.visibleDevices != null && inst.gpu == "rocm") {
          ROCR_VISIBLE_DEVICES = inst.visibleDevices;
        }
        // lib.optionalAttrs (inst.gpu == "rocm" && inst.rocmVersion != "") {
          HSA_OVERRIDE_GFX_VERSION = inst.rocmVersion;
        };
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.llama-swap}/bin/llama-swap -config ${mkSwapConfig inst} -listen 0.0.0.0:${toString inst.port}";
        User = "llama-cpp";
        Group = "llama-cpp";
        WorkingDirectory = home;
        StateDirectory = ["llama-cpp"];
        ReadWritePaths = [home modelsDir];
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
  in {
    options.myNixOS.services.llama-cpp = {
      enable = lib.mkEnableOption "myNixOS.services.llama-cpp";

      models = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Model id exposed via the OpenAI-compatible API";
            };
            repo = lib.mkOption {
              type = lib.types.str;
              description = "HuggingFace repo id (e.g. unsloth/Qwen3.6-27B-GGUF)";
            };
            file = lib.mkOption {
              type = lib.types.str;
              description = "GGUF filename within the repo";
            };
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = ["-ngl" "999" "-c" "16384" "--flash-attn" "on"];
              description = "Extra arguments passed to llama-server";
            };
            ttl = lib.mkOption {
              type = lib.types.int;
              default = 300;
              description = "Seconds of idle before llama-swap unloads this model (0 = never)";
            };
          };
        });
        default = [];
        description = "GGUF models served through llama-swap";
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
              description = "Device selection: CUDA_VISIBLE_DEVICES for cuda, ROCR_VISIBLE_DEVICES for rocm (null = all)";
            };
            port = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              description = "Fixed port for the llama-swap listener (null = auto-assign via port-selector)";
            };
          };
        });
        default = {};
        description = "Named llama-swap instances, each binding to its own port and GPU";
      };
    };

    config = lib.mkIf cfg.enable {
      port-selector.auto-assign = lib.mapAttrsToList (name: _: "llama-cpp-${name}") (
        lib.filterAttrs (_: icfg: icfg.port == null) cfg.instances
      );
      port-selector.set-ports = lib.mapAttrs' (name: icfg:
        lib.nameValuePair (toString icfg.port) "llama-cpp-${name}"
      ) (lib.filterAttrs (_: icfg: icfg.port != null) cfg.instances);

      networking.firewall.allowedTCPPorts = map ({port, ...}: port) instanceList;

      users.users.llama-cpp = {
        isSystemUser = true;
        group = "llama-cpp";
        inherit home;
      };
      users.groups.llama-cpp = {};

      environment.systemPackages =
        [pkgs.llama-swap hfHub]
        ++ lib.unique (map ({pkg, ...}: pkg) instanceList);

      systemd.tmpfiles.rules = [
        "d ${home} 0755 llama-cpp llama-cpp -"
        "d ${modelsDir} 0755 llama-cpp llama-cpp -"
      ];

      systemd.services =
        lib.listToAttrs (
          map (inst: lib.nameValuePair "llama-cpp-${inst.name}" (mkSwapService inst))
          instanceList
        )
        // lib.optionalAttrs (cfg.models != []) {
          llama-cpp-model-loader = {
            description = "Download llama-cpp GGUF models";
            wantedBy = ["multi-user.target"];
            wants = ["network-online.target"];
            after = ["network-online.target"];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "llama-cpp";
              Group = "llama-cpp";
              StateDirectory = ["llama-cpp"];
              Environment = "HF_HOME=${home}/.cache/huggingface";
              ExecStart = pkgs.writeShellScript "llama-cpp-model-loader" ''
                set -euo pipefail
                mkdir -p "$HF_HOME"
                ${lib.concatMapStrings (m: ''
                  dest=${lib.escapeShellArg (dirOf (modelPath m))}
                  target=${lib.escapeShellArg (modelPath m)}
                  mkdir -p "$dest"
                  if [[ ! -f "$target" ]]; then
                    echo "Downloading ${m.repo}/${m.file} -> $target"
                    ${hfHub}/bin/hf download \
                      ${lib.escapeShellArg m.repo} \
                      ${lib.escapeShellArg m.file} \
                      --local-dir "$dest"
                  fi
                '') cfg.models}
              '';
              Restart = "on-failure";
              RestartSec = "30s";
            };
          };
        };
    };
  };
}
