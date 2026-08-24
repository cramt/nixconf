# Fleet metrics. The point isn't uptime alerting -- it's keeping a long history
# of what actually ran, so "which services and packages do I never use?" becomes
# a PromQL query instead of a guess. That's why retention is in years and why
# the systemd/process collectors (both off by default upstream) are on.
#
# Exporters ride along with bundles.general, so every host reports. The server
# runs wherever it's enabled and scrapes the whole fleet by name. Desktops that
# are powered off just scrape-fail, and that's fine: `up == 0` is itself the
# "was this machine even on" signal that any usage ratio has to divide by.
#
# Known blind spot: process-exporter samples /proc on the scrape interval, so a
# binary that runs for ten seconds between scrapes is invisible. Answering "did
# I *ever* run this" properly needs execsnoop/auditd, not polling.
{ ... }: {
  flake.nixosModules."services.metrics" = {
    config,
    lib,
    inputs,
    ...
  }: let
    cfg = config.myNixOS.services.metrics;
    ports = config.port-selector.ports;

    hostsDir = ../../hosts;

    # Same derivation as modules/flake/hosts.nix: hosts/ *is* the fleet, and a
    # host.nix only exists to deviate from the name-derived defaults. Rereading
    # it here keeps the scrape list from becoming a second, driftable copy of
    # the host list.
    hostNames = builtins.attrNames (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir hostsDir)
    );

    addressOf = name: let
      knobs = hostsDir + "/${name}/host.nix";
    in
      if builtins.pathExists knobs
      then (import knobs {inherit inputs;}).address or name
      else name;

    # One static_config per host so every series carries a readable `host`
    # label; prometheus' own `instance` label is the raw address:port.
    fleetJob = jobName: port: {
      job_name = jobName;
      static_configs =
        builtins.map (name: {
          targets = ["${addressOf name}:${toString port}"];
          labels.host = name;
        })
        hostNames;
    };
  in {
    options.myNixOS.services.metrics = {
      exporter = {
        enable = lib.mkEnableOption "myNixOS.services.metrics.exporter";
      };
      server = {
        enable = lib.mkEnableOption "myNixOS.services.metrics.server";
        scrapeInterval = lib.mkOption {
          type = lib.types.str;
          default = "60s";
          description = ''
            Usage questions resolve over weeks, so this trades resolution for
            years of history -- at 60s the fleet writes roughly 75MB/day.
          '';
        };
        retentionTime = lib.mkOption {
          type = lib.types.str;
          default = "2y";
          description = "How long to keep samples. Way past prometheus' 15d default on purpose.";
        };
        retentionSize = lib.mkOption {
          type = lib.types.str;
          default = "40GB";
          description = ''
            Hard cap on the TSDB so it can't eat the root filesystem. Whichever
            of this and retentionTime bites first wins.
          '';
        };
        grafana.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run Grafana alongside prometheus, pre-pointed at it.";
        };
      };
    };

    config = lib.mkMerge [
      {
        # Reserved unconditionally rather than hash-assigned: the server has to
        # address exporters on hosts whose config it never evaluates, so these
        # numbers must be the same everywhere by construction.
        port-selector.set-ports = {
          "9100" = "node_exporter";
          "9256" = "process_exporter";
          "9090" = "prometheus";
          "3000" = "grafana";
        };
      }

      (lib.mkIf cfg.exporter.enable {
        services.prometheus.exporters.node = {
          enable = true;
          port = ports.node_exporter;
          # systemd: which units are loaded/active/failed, and for how long --
          # the direct answer to "is this service enabled but never used".
          # logind: seats and sessions, i.e. was a human actually at the machine.
          # processes: kernel-level process/thread counts, cheap context for the
          # per-binary detail process-exporter provides.
          enabledCollectors = ["systemd" "logind" "processes"];
          extraFlags = ["--collector.systemd.enable-restarts-metrics"];
        };

        services.prometheus.exporters.process = {
          enable = true;
          port = ports.process_exporter;
          # Group every process by its executable's basename. Cardinality is
          # bounded by the set of distinct binaries that run (a few hundred on a
          # desktop), and the basename is what maps back to a package in the
          # config. Grouping per-PID instead would be unbounded.
          settings.process_names = [
            {
              name = "{{.ExeBase}}";
              cmdline = [".+"];
            }
          ];
        };

        # Metrics endpoints are unauthenticated and describe the machine in
        # detail, so this is LAN-only exposure -- the same posture the rest of
        # this fleet already takes (docker's 2375, postgres, btop-over-ttyd).
        networking.firewall.allowedTCPPorts = [
          ports.node_exporter
          ports.process_exporter
        ];
      })

      (lib.mkIf cfg.server.enable {
        services.prometheus = {
          enable = true;
          port = ports.prometheus;
          globalConfig.scrape_interval = cfg.server.scrapeInterval;
          retentionTime = cfg.server.retentionTime;
          # The NixOS module only wires up retention.time, and a time-only
          # bound has no idea how big the fleet's cardinality is.
          extraFlags = ["--storage.tsdb.retention.size=${cfg.server.retentionSize}"];
          scrapeConfigs = [
            (fleetJob "node" ports.node_exporter)
            (fleetJob "process" ports.process_exporter)
          ];
        };

        services.grafana = lib.mkIf cfg.server.grafana.enable {
          enable = true;
          settings = {
            server = {
              # Otherwise root_url points at localhost and grafana's own
              # redirects break for anyone reaching it over the LAN.
              domain = config.networking.hostName;
              http_addr = "0.0.0.0";
              http_port = ports.grafana;
            };
            # Anonymous Admin instead of the stock admin/admin: there's no
            # password to leak or rotate, and on a LAN-bound port it grants
            # exactly what LAN reach already grants. This is load-bearing on
            # http_addr staying off the public internet -- put it behind
            # caddy's basic_auth before exposing it.
            "auth.anonymous" = {
              enabled = true;
              org_role = "Admin";
            };
            auth.disable_login_form = true;
          };
          provision.datasources.settings = {
            apiVersion = 1;
            datasources = [
              {
                name = "Prometheus";
                type = "prometheus";
                access = "proxy";
                url = "http://127.0.0.1:${toString ports.prometheus}";
                isDefault = true;
              }
            ];
          };
        };

        # Open so an agent can hit /api/v1/query from another host on the LAN,
        # which is the entire point of collecting this.
        networking.firewall.allowedTCPPorts =
          [ports.prometheus]
          ++ lib.optional cfg.server.grafana.enable ports.grafana;
      })
    ];
  };
}
