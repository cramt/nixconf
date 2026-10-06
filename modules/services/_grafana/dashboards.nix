# Dashboards as Nix rather than exported JSON: the panels share a handful of
# shapes, and a typo'd field fails eval instead of rendering an
# empty panel. Grafana only sees the toJSON output, read-only.
{
  lib,
  domain,
}: let
  # No datasource on panels or targets: they fall back to the default, the one
  # provisioned prometheus. Pinning it by uid is what grafana#110740 breaks.

  target = refId: {
    expr,
    legend ? "",
    instant ? false,
    format ? "time_series",
  }: {
    inherit refId expr instant format;
    legendFormat = legend;
    range = !instant;
  };

  # Panels are written without positions; `layout` flows them left to right
  # across Grafana's 24-column grid and wraps, so reordering is just moving a
  # line.
  panel = type: {
    title,
    queries,
    w ? 12,
    h ? 8,
    unit ? "short",
    description ? "",
    min ? null,
    max ? null,
    options ? {},
    fieldConfig ? {},
    transformations ? [],
    # Overrides the dashboard range for this panel alone, e.g. "14d".
    timeFrom ? null,
  }: {
    inherit type title description w h options transformations;
    ${if timeFrom != null then "timeFrom" else null} = timeFrom;
    targets = lib.imap0 (i: target (builtins.elemAt ["A" "B" "C" "D" "E" "F"] i)) queries;
    fieldConfig = lib.recursiveUpdate {
      defaults = {inherit unit;} // lib.optionalAttrs (min != null) {inherit min;} // lib.optionalAttrs (max != null) {inherit max;};
      overrides = [];
    } fieldConfig;
  };

  timeseries = args: panel "timeseries" (args // {
    options = lib.recursiveUpdate {
      legend = {
        displayMode = "list";
        placement = "bottom";
      };
      tooltip.mode = "multi";
    } (args.options or {});
  });

  stat = args: panel "stat" ({h = 4; w = 6;} // args // {
    options = lib.recursiveUpdate {
      reduceOptions.calcs = ["lastNotNull"];
      colorMode = "value";
      graphMode = "none";
      textMode = "value_and_name";
    } (args.options or {});
  });

  bars = args: panel "bargauge" ({h = 10;} // args // {
    options = lib.recursiveUpdate {
      displayMode = "basic";
      orientation = "horizontal";
      reduceOptions.calcs = ["lastNotNull"];
      showUnfilled = true;
      valueMode = "text";
    } (args.options or {});
  });

  # One instant query flattened into a sortable table, labels as columns.
  table = args @ {sortBy ? null, ...}:
    panel "table" ({h = 12;} // (removeAttrs args ["sortBy"]) // {
      queries = map (q: q // {instant = true;}) args.queries;
      transformations = [
        {
          id = "labelsToFields";
          options.mode = "columns";
        }
        {
          id = "organize";
          options.excludeByName = {
            Time = true;
            __name__ = true;
            job = true;
          };
        }
      ];
      options = lib.optionalAttrs (sortBy != null) {
        sortBy = [
          {
            displayName = sortBy;
            desc = true;
          }
        ];
      };
    });

  text = content: {
    type = "text";
    title = "";
    w = 24;
    h = 3;
    options = {
      mode = "markdown";
      inherit content;
    };
  };

  layout = panels:
    (lib.foldl' (acc: p: let
      wraps = acc.x + p.w > 24;
      x = if wraps then 0 else acc.x;
      y = if wraps then acc.y + acc.rowH else acc.y;
      rowH = if wraps then p.h else lib.max acc.rowH p.h;
    in {
      x = x + p.w;
      inherit y rowH;
      id = acc.id + 1;
      out = acc.out ++ [
        ((removeAttrs p ["w" "h"]) // {
          inherit (acc) id;
          gridPos = {
            inherit x y;
            inherit (p) w h;
          };
        })
      ];
    }) {
      x = 0;
      y = 0;
      rowH = 0;
      id = 1;
      out = [];
    }
    panels).out;

  dashboard = {
    uid,
    title,
    time ? "now-24h",
    refresh ? "1m",
    panels,
  }: {
    inherit uid title refresh;
    schemaVersion = 39;
    editable = false;
    tags = ["nixconf"];
    timezone = "browser";
    time = {
      from = time;
      to = "now";
    };
    panels = layout panels;
  };

  # Exclude veth/bridge noise; what's left is each host's real NICs.
  physicalNic = ''device!~"lo|veth.*|docker.*|br-.*|virbr.*|tailscale.*|wg.*"'';
  # Bind mounts and subvolumes of one device otherwise each show up as a row.
  realFs = ''fstype!~"tmpfs|ramfs|overlay|squashfs|fuse.*|vfat|nsfs", mountpoint!~"/nix/store|/var/lib/.*"'';
  # remote_write from every agent lands here, so it dwarfs real traffic.
  realVhost = ''host!="metrics.${domain}"'';
in {
  fleet = dashboard {
    uid = "fleet";
    title = "Fleet";
    time = "now-7d";
    panels = [
      (text ''
        Agents push to luna, so a host's `up` is 1 whenever it reports at all. **Missing data means the host was off.**
        ganymede, eros and mercury don't appear until they have `/etc/opnix-token`.
      '')
      (bars {
        title = "Last seen";
        description = "How long since each host last pushed a sample. Looks back 30 days.";
        unit = "s";
        w = 8;
        h = 7;
        queries = [
          {
            expr = ''time() - max by (instance) (max_over_time(timestamp(up{job="node"})[30d:1m]))'';
            legend = "{{instance}}";
            instant = true;
          }
        ];
        options.displayMode = "lcd";
      })
      (bars {
        title = "Hours online in range";
        unit = "h";
        w = 8;
        h = 7;
        queries = [
          {
            expr = ''count_over_time(up{job="node"}[$__range:5m]) / 12'';
            legend = "{{instance}}";
            instant = true;
          }
        ];
      })
      (bars {
        title = "Filesystem used";
        unit = "percent";
        min = 0;
        max = 100;
        w = 8;
        h = 7;
        queries = [
          {
            expr = "100 * (1 - node_filesystem_avail_bytes{${realFs}} / node_filesystem_size_bytes{${realFs}})";
            legend = "{{instance}} {{mountpoint}}";
            instant = true;
          }
        ];
        options.displayMode = "gradient";
        fieldConfig.defaults.thresholds = {
          mode = "absolute";
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "orange";
              value = 80;
            }
            {
              color = "red";
              value = 95;
            }
          ];
        };
      })
      (timeseries {
        title = "CPU busy";
        unit = "percent";
        min = 0;
        max = 100;
        queries = [
          {
            expr = ''100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])))'';
            legend = "{{instance}}";
          }
        ];
      })
      (timeseries {
        title = "Memory used";
        unit = "percent";
        min = 0;
        max = 100;
        queries = [
          {
            expr = "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)";
            legend = "{{instance}}";
          }
        ];
      })
      (timeseries {
        title = "Load (1m)";
        queries = [
          {
            expr = "node_load1";
            legend = "{{instance}}";
          }
        ];
      })
      (timeseries {
        title = "Network";
        description = "Receive above the axis, transmit below.";
        unit = "Bps";
        queries = [
          {
            expr = "sum by (instance) (rate(node_network_receive_bytes_total{${physicalNic}}[$__rate_interval]))";
            legend = "{{instance}} rx";
          }
          {
            expr = "-sum by (instance) (rate(node_network_transmit_bytes_total{${physicalNic}}[$__rate_interval]))";
            legend = "{{instance}} tx";
          }
        ];
      })
    ];
  };

  # The reason the metrics stack exists: evidence for pruning nixconf.
  usage = dashboard {
    uid = "usage";
    title = "Usage audit";
    time = "now-30d";
    refresh = "";
    panels = [
      (text ''
        Evidence for pruning nixconf. **Blind spots:** process-exporter polls every 60s, so short-lived CLIs (`rg`, `jq`, ...) never show up.
        Interpreted apps group under their runtime (`python3.14`, `node`, `app.asar` for electron). For web services, caddy's per-vhost access logs on luna are the stronger signal.
      '')
      (table {
        title = "Days since each process last ran";
        description = "Only covers the dashboard range. A process that never ran in that range doesn't appear at all.";
        unit = "d";
        w = 12;
        h = 16;
        sortBy = "Value";
        queries = [
          {
            expr = "(time() - max by (instance, groupname) (max_over_time(timestamp(namedprocess_namegroup_num_procs > 0)[$__range:1h]))) / 86400";
          }
        ];
      })
      (bars {
        title = "CPU-hours by process";
        # The 1h subquery halves a 30d load (~10s to ~5s on luna) over ~5.7k
        # groups, and keeps the same ranking; it only drops each session's
        # final partial hour, reading 5-10% low.
        description = "Sampled hourly, so totals read 5-10% low. The ranking is accurate.";
        unit = "h";
        w = 12;
        h = 16;
        queries = [
          {
            expr = "topk(30, sum by (instance, groupname) (increase(namedprocess_namegroup_cpu_seconds_total[$__range:1h]))) / 3600";
            legend = "{{instance}} {{groupname}}";
            instant = true;
          }
        ];
      })
      (bars {
        title = "Requests by vhost";
        description = "Includes the constant background of scanners that hits every public vhost. Low numbers here don't mean nobody uses it.";
        w = 12;
        h = 12;
        queries = [
          {
            expr = "sort_desc(sum by (host) (increase(caddy_http_requests_total{${realVhost}}[$__range])))";
            legend = "{{host}}";
            instant = true;
          }
        ];
      })
      (bars {
        title = "Resident memory now";
        unit = "bytes";
        w = 12;
        h = 12;
        queries = [
          {
            expr = ''topk(20, sum by (instance, groupname) (namedprocess_namegroup_memory_bytes{memtype="resident"}))'';
            legend = "{{instance}} {{groupname}}";
            instant = true;
          }
        ];
      })
    ];
  };

  luna = dashboard {
    uid = "luna";
    title = "luna services";
    panels = [
      (stat {
        title = "Arr health issues";
        description = "Open warnings in each app's System > Status page.";
        queries = [
          {
            expr = ''label_replace(sum by (job) ({__name__=~"(sonarr|radarr|prowlarr|bazarr)_system_health_issues"}), "app", "$1", "job", "exportarr-(.*)")'';
            legend = "{{app}}";
          }
        ];
        w = 8;
        fieldConfig.defaults.thresholds = {
          mode = "absolute";
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "orange";
              value = 1;
            }
          ];
        };
      })
      (stat {
        title = "Missing";
        queries = [
          {
            expr = "sum(sonarr_episode_missing_total)";
            legend = "episodes";
          }
          {
            expr = "sum(radarr_movie_missing_total)";
            legend = "movies";
          }
          {
            expr = "sum(bazarr_subtitles_missing_total)";
            legend = "subtitles";
          }
        ];
        w = 8;
      })
      (stat {
        title = "Indexers";
        queries = [
          {
            expr = "sum(prowlarr_indexer_enabled_total)";
            legend = "enabled";
          }
          {
            expr = "sum(prowlarr_indexer_unavailable)";
            legend = "unavailable";
          }
        ];
        w = 8;
        fieldConfig.overrides = [
          {
            matcher = {
              id = "byName";
              options = "unavailable";
            };
            properties = [
              {
                id = "thresholds";
                value = {
                  mode = "absolute";
                  steps = [
                    {
                      color = "green";
                      value = null;
                    }
                    {
                      color = "orange";
                      value = 1;
                    }
                  ];
                };
              }
            ];
          }
        ];
      })
      (timeseries {
        title = "GPU utilisation";
        description = "Encoder/decoder busy means Jellyfin is transcoding on NVENC.";
        unit = "percentunit";
        min = 0;
        max = 1;
        queries = [
          {
            expr = "nvidia_smi_utilization_gpu_ratio";
            legend = "gpu";
          }
          {
            expr = "nvidia_smi_utilization_encoder_ratio";
            legend = "encoder";
          }
          {
            expr = "nvidia_smi_utilization_decoder_ratio";
            legend = "decoder";
          }
        ];
      })
      (timeseries {
        title = "GPU memory, temperature, power";
        queries = [
          {
            expr = "nvidia_smi_memory_used_bytes / nvidia_smi_memory_total_bytes * 100";
            legend = "vram %";
          }
          {
            expr = "nvidia_smi_temperature_gpu";
            legend = "°C";
          }
          {
            expr = "nvidia_smi_power_draw_watts";
            legend = "W";
          }
        ];
      })
      (timeseries {
        title = "Requests by vhost";
        unit = "reqps";
        queries = [
          {
            expr = "sum by (host) (rate(caddy_http_requests_total{${realVhost}}[$__rate_interval]))";
            legend = "{{host}}";
          }
        ];
      })
      (timeseries {
        title = "5xx by vhost";
        unit = "reqps";
        queries = [
          {
            expr = ''sum by (host) (rate(caddy_http_request_duration_seconds_count{code=~"5..", ${realVhost}}[$__rate_interval]))'';
            legend = "{{host}}";
          }
        ];
      })
      (timeseries {
        title = "p95 response time by vhost";
        description = "Long-lived streams (jellyfin playback, t3 websockets) inflate this. Compare a vhost against itself over time.";
        unit = "s";
        queries = [
          {
            expr = "histogram_quantile(0.95, sum by (host, le) (rate(caddy_http_request_duration_seconds_bucket{${realVhost}}[$__rate_interval])))";
            legend = "{{host}}";
          }
        ];
      })
      (timeseries {
        title = "Arr root folder free space";
        unit = "bytes";
        queries = [
          {
            expr = ''{__name__=~"(sonarr|radarr)_rootfolder_freespace_bytes"}'';
            legend = "{{path}}";
          }
        ];
      })
    ];
  };

  claude = let
    # Anthropic's reset time wobbles by a second between polls (21:59:59 vs
    # 22:00:00); unrounded, every wobble would split a window into two bars.
    # Grafana's date units want milliseconds.
    resetAtMs = selector: "round(cliproxy_quota_reset_timestamp_seconds${selector} / 60) * 60 * 1000";

    byName = name: properties: {
      matcher = {
        id = "byName";
        options = name;
      };
      inherit properties;
    };

    windowNames = {
      id = "mappings";
      value = [
        {
          type = "value";
          options = {
            five_hour.text = "5-hour";
            seven_day.text = "7-day";
          };
        }
      ];
    };

    remainingThresholds = {
      mode = "absolute";
      steps = [
        {
          color = "red";
          value = null;
        }
        {
          color = "orange";
          value = 0.2;
        }
        {
          color = "green";
          value = 0.5;
        }
      ];
    };

    # Every sample within one quota window carries the same reset time, so a
    # state timeline over it draws each window as one bar, open to reset.
    windowTimeline = {
      title,
      window,
      timeFrom,
      format,
    }:
      panel "state-timeline" {
        inherit title timeFrom;
        description = "One bar per quota window, labelled with when it resets. Bars that end together compete for the same days.";
        w = 24;
        h = 6;
        unit = "time:${format}";
        queries = [
          {
            expr = resetAtMs ''{window="${window}"}'';
            legend = "{{email}}";
          }
        ];
        options = {
          mergeValues = true;
          showValue = "always";
          alignValue = "left";
          rowHeight = 0.8;
          legend.showLegend = false;
        };
        fieldConfig.defaults = {
          color = {
            mode = "fixed";
            fixedColor = "#a9744f";
          };
          custom = {
            fillOpacity = 70;
            lineWidth = 2;
          };
        };
      };
  in dashboard {
    uid = "claude-pool";
    title = "Claude pool";
    panels = [
      (panel "table" {
        title = "Quota";
        description = "Remaining share of each window, as Anthropic reports it.";
        w = 16;
        h = 7;
        queries = map (q: q // {instant = true; format = "table";}) [
          {expr = "cliproxy_quota_remaining_ratio";}
          {expr = resetAtMs "";}
          {expr = "cliproxy_quota_reset_timestamp_seconds - time()";}
        ];
        transformations = [
          {
            id = "merge";
            options = {};
          }
          {
            id = "organize";
            options = {
              excludeByName = lib.genAttrs ["Time" "instance" "job" "plugin_id" "auth_index" "provider"] (_: true);
              renameByName = {
                "Value #A" = "Remaining";
                "Value #B" = "Resets";
                "Value #C" = "In";
              };
              indexByName = {
                email = 0;
                window = 1;
                "Value #A" = 2;
                "Value #B" = 3;
                "Value #C" = 4;
              };
            };
          }
        ];
        options.sortBy = [
          {
            displayName = "email";
            desc = false;
          }
        ];
        fieldConfig.overrides = [
          (byName "window" [windowNames])
          (byName "Remaining" [
            {
              id = "unit";
              value = "percentunit";
            }
            {
              id = "min";
              value = 0;
            }
            {
              id = "max";
              value = 1;
            }
            {
              id = "thresholds";
              value = remainingThresholds;
            }
            {
              id = "custom.cellOptions";
              value = {
                type = "gauge";
                mode = "basic";
              };
            }
          ])
          (byName "Resets" [
            {
              id = "unit";
              value = "time:ddd MM/DD HH:mm";
            }
          ])
          (byName "In" [
            {
              id = "unit";
              value = "dtdurations";
            }
          ])
        ];
      })
      (table {
        title = "Credentials";
        w = 8;
        h = 7;
        queries = [{expr = "cliproxy_credentials";}];
        fieldConfig.overrides = [
          (byName "Value" [
            {
              id = "custom.hidden";
              value = true;
            }
          ])
        ];
      })
      (windowTimeline {
        title = "7-day windows";
        window = "seven_day";
        timeFrom = "14d";
        format = "MM/DD HH:mm";
      })
      (windowTimeline {
        title = "5-hour windows";
        window = "five_hour";
        timeFrom = "48h";
        format = "HH:mm";
      })
      (timeseries {
        title = "Quota remaining";
        description = "How fast each window burns down.";
        unit = "percentunit";
        min = 0;
        max = 1;
        w = 24;
        queries = [
          {
            expr = "cliproxy_quota_remaining_ratio";
            legend = "{{email}} {{window}}";
          }
        ];
      })
      (timeseries {
        title = "Requests by model";
        unit = "reqps";
        w = 24;
        queries = [
          {
            expr = "sum by (model) (rate(cliproxy_requests_total[$__rate_interval]))";
            legend = "{{model}}";
          }
        ];
      })
      (bars {
        title = "Tokens in range";
        w = 12;
        queries = [
          {
            expr = "sort_desc(sum by (model, type) (increase(cliproxy_tokens_total[$__range])))";
            legend = "{{model}} {{type}}";
            instant = true;
          }
        ];
      })
      (timeseries {
        title = "Failures by status";
        unit = "reqps";
        w = 12;
        h = 10;
        queries = [
          {
            expr = "sum by (code, email) (rate(cliproxy_failures_total[$__rate_interval]))";
            legend = "{{code}} {{email}}";
          }
        ];
      })
      (timeseries {
        title = "Latency by model";
        unit = "s";
        w = 24;
        queries = [
          {
            expr = "histogram_quantile(0.5, sum by (model, le) (rate(cliproxy_request_duration_seconds_bucket[$__rate_interval])))";
            legend = "{{model}} p50";
          }
          {
            expr = "histogram_quantile(0.95, sum by (model, le) (rate(cliproxy_request_duration_seconds_bucket[$__rate_interval])))";
            legend = "{{model}} p95";
          }
        ];
      })
    ];
  };
}
