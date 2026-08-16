{...}: {
  flake.nixosModules."services.colibri" = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.myNixOS.services.colibri;

    port =
      if cfg.serve.port != null
      then cfg.serve.port
      else config.port-selector.ports."colibri";

    # Selected by name, not .override'd, so this resolves to the same store path
    # CI prebuilds into cachix (see overlays/default.nix) — a local .override
    # here would silently become a from-source HIP build on the desktop.
    pkg =
      {
        cpu = pkgs.colibri;
        rocm = pkgs.colibri-rocm;
        vulkan = pkgs.colibri-vulkan;
      }
      .${cfg.backend};
  in {
    options.myNixOS.services.colibri = {
      # Deliberately split from serve.enable. `coli` is a whole toolbox you need
      # BEFORE a model exists — convert, download, doctor, plan, tune, mirror,
      # iobench — and staging 167-372GB of weights is a manual step by nature.
      # Folding both into one switch would mean either shipping a daemon that
      # crash-loops against an empty directory or having no CLI to populate it.
      enable = lib.mkEnableOption "myNixOS.services.colibri (installs the `coli` CLI)";

      backend = lib.mkOption {
        type = lib.types.enum ["cpu" "rocm" "vulkan"];
        default = "cpu";
        description = ''
          GPU tier. "cpu" streams experts into host RAM only. "rocm" is the HIP
          backend built for gfx1101 (RX 7800 XT). "vulkan" is the RADV compute
          path, which upstream measures ~35% faster than HIP on RDNA4 —
          unmeasured on RDNA3, so A/B them rather than assuming.
        '';
      };

      serve = {
        enable = lib.mkEnableOption "the colibrì OpenAI-compatible API daemon";

        # No default on purpose: a daemon with nowhere to read weights from is
        # not a state worth being able to express.
        model = lib.mkOption {
          type = lib.types.path;
          description = ''
            Model directory (COLI_MODEL) — the primary copy. This wants a
            dedicated non-CoW, uncompressed filesystem; on btrfs with
            compression the engine cannot use O_DIRECT at all, and int4 weights
            do not compress anyway.
          '';
          example = "/llm/primary/deepseek-v4-flash";
        };

        mirror = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Second copy of the model on a DIFFERENT physical drive
            (COLI_MODEL_MIRROR). Expert reads are hashed across both drives and
            their bandwidth sums. May be partial — divergent or missing shards
            fall back to the primary, so staging just the hottest ones with
            `coli mirror stage` still helps.

            Pointless unless it really is a separate drive: two paths on one
            filesystem cost double the space for no bandwidth.
          '';
          example = "/llm/mirror/deepseek-v4-flash";
        };

        direct = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Set DIRECT=1 (O_DIRECT), bypassing the page cache. Upstream measures
            +34% decode on drives with DRAM and bandwidth headroom, but "neutral
            to negative" on DRAM-less or QLC ones. Off by default because it is
            a per-drive empirical question — measure it, keep what wins.
          '';
        };

        memoryMax = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            systemd MemoryMax for the engine. On a machine that is also a daily
            driver this is the difference between a run that degrades and a run
            that takes the session with it — GLM-5.2's resident dense weights
            alone are ~10GB before any expert cache.
          '';
          example = "20G";
        };

        port = lib.mkOption {
          type = lib.types.nullOr lib.types.port;
          default = null;
          description = "API port (null = auto-assign via port-selector).";
        };

        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = ''
            Bind address. Loopback by default: the endpoint has no auth of its
            own, so exposing it should be a deliberate act.
          '';
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Open the API port in the firewall.";
        };

        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = ''
            Extra engine tuning knobs — PIN_GB, CACHE, PIPE, PILOT,
            COLI_DISK_WEIGHTS and friends. Whatever `coli tune` measures belongs
            here, so the tuned profile is declarative rather than a line of
            shell history on one machine.
          '';
          example = {
            PILOT = "1";
            PIN_GB = "all";
          };
        };
      };
    };

    config = lib.mkMerge [
      (lib.mkIf cfg.enable {
        environment.systemPackages = [pkg];
      })

      (lib.mkIf (cfg.enable && cfg.serve.enable) {
        port-selector.auto-assign = lib.optional (cfg.serve.port == null) "colibri";
        port-selector.set-ports = lib.optionalAttrs (cfg.serve.port != null) {
          "${toString cfg.serve.port}" = "colibri";
        };

        networking.firewall.allowedTCPPorts = lib.optional cfg.serve.openFirewall port;

        users.users.colibri = {
          isSystemUser = true;
          group = "colibri";
          extraGroups = lib.optionals (cfg.backend != "cpu") ["render" "video"];
        };
        users.groups.colibri = {};

        systemd.services.colibri = {
          description = "colibrì MoE inference server";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];

          # The weights live on their own filesystem and disko mounts those
          # nofail, so without this the unit races the mount and fails with a
          # confusing "model not found" against an empty mountpoint.
          unitConfig.RequiresMountsFor =
            [cfg.serve.model] ++ lib.optional (cfg.serve.mirror != null) cfg.serve.mirror;

          environment =
            {
              COLI_MODEL = toString cfg.serve.model;
            }
            // lib.optionalAttrs (cfg.serve.mirror != null) {
              COLI_MODEL_MIRROR = toString cfg.serve.mirror;
            }
            // lib.optionalAttrs cfg.serve.direct {
              DIRECT = "1";
            }
            // cfg.serve.environment;

          serviceConfig =
            {
              Type = "exec";
              ExecStart = lib.concatStringsSep " " [
                (lib.getExe pkg)
                "serve"
                "--host"
                cfg.serve.host
                "--port"
                (toString port)
              ];
              User = "colibri";
              Group = "colibri";
              Restart = "on-failure";
              RestartSec = "5";

              # The engine only reads weights and serves HTTP.
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
              ReadOnlyPaths =
                [cfg.serve.model] ++ lib.optional (cfg.serve.mirror != null) cfg.serve.mirror;
            }
            // lib.optionalAttrs (cfg.serve.memoryMax != null) {
              MemoryMax = cfg.serve.memoryMax;
              # Reclaim before the hard cap rather than at it, so an overshoot
              # sheds page cache instead of being OOM-killed outright.
              MemoryHigh = cfg.serve.memoryMax;
            }
            // lib.optionalAttrs (cfg.backend != "cpu") {
              PrivateDevices = false;
              DevicePolicy = "closed";
              DeviceAllow = ["char-drm" "char-kfd"];
              SupplementaryGroups = ["render" "video"];
            };
        };
      })
    ];
  };
}
