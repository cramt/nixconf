# Fleet metrics. The point isn't uptime alerting -- it's keeping a long history
# of what actually ran, so "which services and packages do I never use?" becomes
# a PromQL query instead of a guess. That's why retention is in years and why
# the systemd/process collectors (both off by default upstream) are on.
#
# Push, not pull. Machines aren't always on the home LAN and opening an exporter
# port on a laptop that roams onto untrusted wifi is not on, so nothing is
# scraped across the network: exporters bind to loopback, each host runs
# prometheus in *agent* mode against its own loopback, and the agent
# remote_writes out to caddy over HTTPS. That's outbound-only, so NAT and
# firewalls stop mattering and the fleet keeps reporting from anywhere.
#
# The cost of push is that "was this machine on" is no longer the `up` series --
# every agent scrapes itself, so up==1 whenever it reports at all. Absence *is*
# the signal now: no samples for a host over a window means it was off or
# offline. `absent_over_time(up{instance="saturn"}[1h])` asks it directly.
#
# Known blind spot either way: process-exporter samples /proc on the scrape
# interval, so a binary that runs for ten seconds between scrapes is invisible.
# Answering "did I *ever* run this" properly needs execsnoop/auditd, not polling.
{ ... }: {
  flake.nixosModules."services.metrics" = {
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.services.metrics;
    ports = config.port-selector.ports;
    site = import ../../myLib/site.nix;

    hostName = config.networking.hostName;

    # Pushing needs the shared credential, and that only exists where opnix
    # does. Hosts without it still run exporters (curl-able on loopback) but
    # stay out of the fleet view until they get an /etc/opnix-token.
    runAgent = cfg.exporter.enable && !cfg.server.enable && config.myNixOS.opnix-secrets.enable;

    # Every agent scrapes 127.0.0.1, so without pinning `instance` here every
    # host would report the same target and only be tellable apart by accident.
    localJob = jobName: port: {
      job_name = jobName;
      static_configs = [
        {
          targets = ["127.0.0.1:${toString port}"];
          labels.instance = hostName;
        }
      ];
    };
  in {
    options.myNixOS.services.metrics = {
      exporter = {
        enable = lib.mkEnableOption "myNixOS.services.metrics.exporter";
      };
      server = {
        enable = lib.mkEnableOption "myNixOS.services.metrics.server";
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "metrics";
          description = ''
            Caddy vhost the agents push to. Needs a matching A record -- these
            are enumerated in infra/main.tf, there's no wildcard.
          '';
        };
        grafanaSubdomain = lib.mkOption {
          type = lib.types.str;
          default = "grafana";
          description = "Caddy vhost for the dashboards. Also needs an A record.";
        };
        dataDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/pool/prometheus";
          description = ''
            Where the TSDB actually lives. Prometheus' stateDir is always a bare
            name under /var/lib, so pointing it at a big disk has to be a bind
            mount; null leaves it on the root filesystem.
          '';
        };
        dataDirDepends = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          example = ["/pool"];
          description = ''
            Mount points the bind source sits on, so the bind is ordered after
            them. Stated rather than derived from config.fileSystems, because
            reading that while defining a member of it is infinite recursion.
          '';
        };
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
          default = "200GB";
          description = ''
            Hard cap on the TSDB. Whichever of this and retentionTime bites
            first wins.
          '';
        };
        auth = {
          username = lib.mkOption {
            type = lib.types.str;
            default = "fleet";
            description = "Basic-auth user the agents push as.";
          };
          hashedPassword = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              bcrypt hash of the push password, from `caddy hash-password`. A
              hash, not a secret, so it lives in the store like btopttyd's does
              -- the password itself comes from opnix on each agent.

              This one credential also fronts grafana, which runs anonymous-
              Admin behind it: whoever can push can also edit dashboards.
            '';
          };
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
        # Pinned rather than hash-assigned purely so they're the familiar
        # numbers when curl-ing an exporter by hand; nothing binds off-host.
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
          # Loopback only: these endpoints are unauthenticated and describe the
          # machine in detail. Nothing off-host ever needs to reach them.
          listenAddress = "127.0.0.1";
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
          listenAddress = "127.0.0.1";
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
      })

      (lib.mkIf runAgent {
        services.prometheus = {
          enable = true;
          enableAgentMode = true;
          port = ports.prometheus;
          listenAddress = "127.0.0.1";
          globalConfig.scrape_interval = cfg.server.scrapeInterval;
          scrapeConfigs = [
            (localJob "node" ports.node_exporter)
            (localJob "process" ports.process_exporter)
          ];
          remoteWrite = [
            {
              url = "https://${cfg.server.subdomain}.${site.domain}/api/v1/write";
              basic_auth = {
                username = cfg.server.auth.username;
                # password_file, not password: keeps the credential out of the
                # world-readable nix store.
                password_file = config.services.onepassword-secrets.secretPaths.metricsRemoteWritePassword;
              };
            }
          ];
        };
      })

      (lib.mkIf cfg.server.enable {
        # A required credential belongs in an assertion, not a placeholder
        # string: an invalid bcrypt hash would let caddy start and then reject
        # every agent, which looks like a network fault rather than a missing
        # secret.
        assertions = [
          {
            assertion = cfg.server.auth.hashedPassword != null;
            message = "myNixOS.services.metrics.server.auth.hashedPassword is unset; generate one with `caddy hash-password` (the agents authenticate against it).";
          }
        ];

        services.prometheus = {
          enable = true;
          port = ports.prometheus;
          # Caddy is the only thing that talks to it, and caddy is local.
          listenAddress = "127.0.0.1";
          globalConfig.scrape_interval = cfg.server.scrapeInterval;
          retentionTime = cfg.server.retentionTime;
          extraFlags = [
            # The receiving half of the push design; off by default.
            "--web.enable-remote-write-receiver"
            # The NixOS module only wires up retention.time, and a time-only
            # bound has no idea how big the fleet's cardinality is.
            "--storage.tsdb.retention.size=${cfg.server.retentionSize}"
          ];
          # The server has no agent, so it scrapes its own loopback exporters
          # directly rather than pushing to itself.
          scrapeConfigs = [
            (localJob "node" ports.node_exporter)
            (localJob "process" ports.process_exporter)
          ];
        };

        fileSystems = lib.mkIf (cfg.server.dataDir != null) {
          "/var/lib/${config.services.prometheus.stateDir}" = {
            device = cfg.server.dataDir;
            fsType = "none";
            options = ["bind"];
            depends = cfg.server.dataDirDepends;
          };
        };

        # Withheld until the credential exists, so the assertion above is what
        # surfaces rather than a type error deep in the Caddyfile builder.
        myNixOS.services.caddy.serviceMap = lib.optionalAttrs (cfg.server.auth.hashedPassword != null) (
          {
            ${cfg.server.subdomain} = {
              port = ports.prometheus;
              basic-auth = {
                username = cfg.server.auth.username;
                hashed-password = cfg.server.auth.hashedPassword;
              };
            };
          }
          // lib.optionalAttrs cfg.server.grafana.enable {
            ${cfg.server.grafanaSubdomain} = {
              port = ports.grafana;
              basic-auth = {
                username = cfg.server.auth.username;
                hashed-password = cfg.server.auth.hashedPassword;
              };
            };
          }
        );

        services.grafana = lib.mkIf cfg.server.grafana.enable {
          enable = true;
          settings = {
            server = {
              http_addr = "127.0.0.1";
              http_port = ports.grafana;
              domain = "${cfg.server.grafanaSubdomain}.${site.domain}";
              root_url = "https://${cfg.server.grafanaSubdomain}.${site.domain}/";
            };
            # Anonymous Admin rather than the stock admin/admin: there's no
            # second password to leak or rotate, and caddy's basic_auth in front
            # is already the gate. Load-bearing on http_addr staying loopback.
            "auth.anonymous" = {
              enabled = true;
              org_role = "Admin";
            };
            auth.disable_login_form = true;
            # File provider rather than a literal: grafana reads it at start-up
            # so the key never lands in the world-readable nix store.
            security.secret_key = "$__file{${config.services.onepassword-secrets.secretPaths.grafanaSecretKey}}";
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
      })
    ];
  };
}
