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

        autoStart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Start at boot. Turn this off on a machine where the engine competes
            with a desktop session for RAM: GLM-5.2 wants ~20GB free and a
            logged-in session can easily be holding that, in which case the
            engine refuses to start rather than be OOM-killed — and a unit that
            refuses at boot just burns restarts. With this off the unit is still
            fully declared, you just decide when: `systemctl start colibri`.
          '';
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "colibri";
          description = ''
            User to run the engine as. The default creates a locked-down system
            user, which is right for a headless host.

            On a workstation, set this to the human who also runs `coli chat`.
            `.coli_usage` — the learned expert-routing history that drives both
            the hit rate and `coli mirror plan` — lives NEXT TO THE MODEL, so
            the daemon and the interactive CLI must be the same identity or they
            keep separate histories (and a system user cannot write into a
            model directory the human downloaded).
          '';
          example = "cramt";
        };

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

        vram = lib.mkOption {
          type = lib.types.nullOr lib.types.number;
          default = null;
          description = ''
            VRAM budget in GB for the routed-expert tier (`--vram`). null lets
            the planner take what it wants, which on a single-GPU desktop is
            nearly all of it — 13.3 of 16 GB measured on saturn, which is enough
            to evict the compositor and kill Electron apps outright.

            This is `memoryMax`'s counterpart for VRAM: set it below total VRAM
            so the desktop keeps a working set. Unlike `memoryMax` it is a
            request to the planner rather than a kernel-enforced cap, so it
            shapes placement instead of failing a run.
          '';
          example = 10;
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

        # Only when we own the identity: pointing serve.user at an existing human
        # must not redeclare that account.
        users.users = lib.optionalAttrs (cfg.serve.user == "colibri") {
          colibri = {
            isSystemUser = true;
            group = "colibri";
            extraGroups = lib.optionals (cfg.backend != "cpu") ["render" "video"];
          };
        };
        users.groups = lib.optionalAttrs (cfg.serve.user == "colibri") {colibri = {};};

        systemd.services.colibri = {
          description = "colibrì MoE inference server";
          wantedBy = lib.optionals cfg.serve.autoStart ["multi-user.target"];
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
            // lib.optionalAttrs (cfg.backend != "cpu") {
              # The VRAM expert tier keeps a host-RAM copy of everything it
              # places in VRAM unless this is set, so on a single GPU the tier
              # costs its size TWICE. On saturn that put the projected peak at
              # 19.0 GB and the engine refused to start rather than be
              # OOM-killed mid-generation. Upstream: "CUDA_RELEASE_HOST=1 frees
              # them for the RAM tier and is what this topology usually
              # wants" (#686). Listed before serve.environment so it stays
              # overridable.
              CUDA_RELEASE_HOST = "1";
            }
            // cfg.serve.environment;

          serviceConfig =
            {
              Type = "exec";
              # --auto-tier is NOT optional on a GPU backend, and its absence is
              # invisible rather than loud. On Linux a bare `coli serve` runs
              # CPU-only even on a HIP build with a working GPU: the launcher's
              # auto-enable path is `sys.platform == "win32"`-scoped, so nothing
              # sets COLI_CUDA and the whole VRAM tier is silently skipped.
              # Upstream hit the same trap hard enough to note that --gpu/--vram
              # without --auto-tier "were silently ignored and the run started
              # CPU-only with no warning — 'GPU' benchmarks published by
              # mistake" (#121). `coli doctor` still reports the GPU as fine,
              # because the PLANNER sees it; only the run doesn't use it.
              ExecStart = lib.concatStringsSep " " ([
                  (lib.getExe pkg)
                  "serve"
                  "--host"
                  cfg.serve.host
                  "--port"
                  (toString port)
                ]
                ++ lib.optionals (cfg.backend != "cpu") ["--auto-tier"]
                ++ lib.optionals (cfg.backend != "cpu" && cfg.serve.vram != null) [
                  "--vram"
                  (toString cfg.serve.vram)
                ]);
              User = cfg.serve.user;
              Restart = "on-failure";
              # Slow, and capped. "not enough free RAM" is a legitimate,
              # persistent failure here — the engine checks its projected peak
              # against available memory and exits rather than being OOM-killed
              # mid-generation. Retrying that every 5s forever just spams the
              # journal while the desktop is using the RAM, so back off and give
              # up; `systemctl start colibri` once you have freed some.
              RestartSec = "30";
              StartLimitBurst = 3;
              StartLimitIntervalSec = 300;

              # The engine serves HTTP and reads weights — but it also WRITES
              # `.coli_usage` (and KV state) into the model directory, which is
              # the learning cache behind both the expert hit rate and
              # `coli mirror plan`. Marking the model read-only would silently
              # disable that: `coli doctor` reports it as
              # `storage.persistence  model directory is read-only`, the hit
              # rate stops improving, and a restage ranks on stale history.
              # The mirror really is read-only — the engine only ever reads
              # replicas, and `coli mirror stage` is a separate manual step.
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
              ReadWritePaths = [cfg.serve.model];
              ReadOnlyPaths = lib.optional (cfg.serve.mirror != null) cfg.serve.mirror;

              # ProtectHome=true hides /home, so an engine running as a human
              # user still must not depend on it. Give it a state dir instead.
              StateDirectory = "colibri";
              Environment = ["HOME=/var/lib/colibri"];
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
