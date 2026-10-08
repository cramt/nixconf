# Intel iGPU metrics. Unlike nvidia (nvidia_gpu_exporter) and amdgpu (node's
# drm + hwmon collectors) nothing in nixpkgs exports i915, so this bridges
# intel_gpu_top's CSV mode into node_exporter's textfile collector: per-engine
# busy (render, video = QuickSync, ...), clocks, RC6 and RAPL GPU power.
{...}: {
  flake.nixosModules."features.intel-gpu" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.intel-gpu;
    dir = "/run/intel-gpu-metrics";

    # intel_gpu_top averages over its whole period, so sampling at the scrape
    # interval means each scrape sees the full minute instead of a slice of it.
    periodMs = 60000;

    # Header-driven, because the engine columns differ per GPU generation
    # (CCS only on newer parts). Families are buffered and printed grouped:
    # the text format rejects a family whose lines aren't contiguous, and the
    # CSV interleaves them per engine.
    toProm = pkgs.writeText "intel-gpu-top-to-prom.awk" ''
      BEGIN {
        FS = ","
        split("RCS:render BCS:copy VCS:video VECS:video_enhance CCS:compute", pairs, " ")
        for (i in pairs) { split(pairs[i], kv, ":"); engines[kv[1]] = kv[2] }
        kinds["%"] = "busy"; kinds["se"] = "semaphore"; kinds["wa"] = "wait"
      }
      NR == 1 { for (i = 1; i <= NF; i++) header[i] = $i; next }
      {
        delete out
        for (i = 1; i <= NF; i++) {
          h = header[i]; v = $i
          if (h == "Freq MHz req") add("intel_gpu_frequency_hertz", "kind=\"requested\"", v * 1e6)
          else if (h == "Freq MHz act") add("intel_gpu_frequency_hertz", "kind=\"actual\"", v * 1e6)
          else if (h == "IRQ /s") add("intel_gpu_interrupts_per_second", "", v)
          else if (h == "RC6 %") add("intel_gpu_rc6_ratio", "", v / 100)
          else if (h == "Power W gpu") add("intel_gpu_power_watts", "domain=\"gpu\"", v)
          else if (h == "Power W pkg") add("intel_gpu_power_watts", "domain=\"package\"", v)
          else if (split(h, p, " ") == 2) {
            eng = (p[1] in engines) ? engines[p[1]] : tolower(p[1])
            if (p[2] in kinds) add("intel_gpu_engine_" kinds[p[2]] "_ratio", "engine=\"" eng "\"", v / 100)
          }
        }
        # Not *.prom, or a scrape mid-write would read it as a second file.
        tmp = "${dir}/intel_gpu.prom.tmp"
        for (m in out) { print "# TYPE " m " gauge" > tmp; printf "%s", out[m] > tmp }
        close(tmp)
        system("${pkgs.coreutils}/bin/mv -f " tmp " ${dir}/intel_gpu.prom")
      }
      function add(m, labels, v) { out[m] = out[m] m (labels == "" ? "" : "{" labels "}") " " v "\n" }
    '';
  in {
    options.myNixOS.intel-gpu.enable = lib.mkEnableOption "myNixOS.intel-gpu";

    config = lib.mkMerge [
      (lib.mkIf cfg.enable {
        # btop reads the same i915 PMU, so it needs CAP_PERFMON too. /run/wrappers/bin
        # comes first in PATH, so this shadows the home-manager btop while still
        # reading its ~/.config.
        security.wrappers.btop = {
          owner = "root";
          group = "root";
          capabilities = "cap_perfmon+ep";
          source = lib.getExe pkgs.btop;
        };
      })
      (lib.mkIf (cfg.enable && config.myNixOS.services.metrics.exporter.enable) {
        systemd.services.intel-gpu-metrics = {
          description = "intel_gpu_top -> node_exporter textfile";
          wantedBy = ["multi-user.target"];
          script = ''
            ${pkgs.intel-gpu-tools}/bin/intel_gpu_top -c -s ${toString periodMs} \
              | ${pkgs.gawk}/bin/awk -f ${toProm}
          '';
          serviceConfig = {
            DynamicUser = true;
            # The i915 PMU and RAPL perf events are all it reads; perf_event_paranoid
            # is 2, so without this it gets nothing.
            AmbientCapabilities = ["CAP_PERFMON"];
            CapabilityBoundingSet = ["CAP_PERFMON"];
            # Removed on stop, so a dead bridge reads as missing data rather than
            # its last sample frozen forever.
            RuntimeDirectory = "intel-gpu-metrics";
            RuntimeDirectoryMode = "0755";
            Restart = "always";
            RestartSec = 30;
          };
        };

        services.prometheus.exporters.node.extraFlags = ["--collector.textfile.directory=${dir}"];
      })
    ];
  };
}
