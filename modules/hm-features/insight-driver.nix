# progress-engine's insight driver (crates/vivisurgeons-insight/driver), run
# unattended on whatever Claude pool quota would otherwise go to waste.
#
# A timer offers it one batch at a time; ExecCondition asks prometheus whether
# the pool is under pace. "Under pace" is per window, not in total: an account's
# 7-day surplus is what's left minus the share of the window still to run, so
# idle nights bank surplus and the driver spends only that, never what a busy
# week of hand-driven work needs. The surplus is summed over the pool because an
# exhausted account's demand spills onto the others. One batch measured
# 2026-10-13 cost ~0.06 of a 7-day window and ~0.4 of a 5-hour one, which is
# what the defaults below leave room for.
#
# The driver works in its own worktree on `branch`, merging origin/main in
# before every batch; merge the branch into main (merge or fast-forward, never
# squash) to take its work. A stop that needs a human (milestone to pin,
# repeated failures, git trouble) exits 3, which stops the timer: look at
# escalations.md in the state dir, then `systemctl --user start insight-driver.timer`.
#
# Every gate check and run lands in <stateDir>/metrics.prom as insight_driver_*,
# for tuning minSlack/minFiveHour against what batches actually burn: overlay
# insight_driver_running on cliproxy_quota_remaining_ratio. The host links the
# file into node_exporter with myNixOS.services.metrics.textfiles.
{ ... }: {
  hmModules.features.insight-driver = { config, lib, pkgs, osConfig, ... }: let
    cfg = config.myHomeManager.insight-driver;
    prometheus = "http://127.0.0.1:${toString osConfig.port-selector.ports.prometheus}";

    state = lib.escapeShellArg cfg.stateDir;

    # metrics.prom, rebuilt whole from the gate's last verdict, the run marks
    # and the driver's own files, so no producer has to edit another's lines.
    # The textfile collector (myNixOS.services.metrics.textfiles) exports it.
    renderMetrics = pkgs.writeShellApplication {
      name = "insight-driver-metrics";
      runtimeInputs = [pkgs.jq pkgs.coreutils];
      text = ''
        json() { if [ -s "$1" ]; then cat "$1"; else echo null; fi; }
        batches='[]'
        if [ -s ${state}/metrics.jsonl ]; then
          batches=$(jq -sc '[.[] | select(.batch)]' ${state}/metrics.jsonl)
        fi
        jq -nr \
          --argjson gate "$(json ${state}/gate.json)" \
          --argjson run "$(json ${state}/run.json)" \
          --argjson driver "$(json ${state}/state.json)" \
          --argjson batches "$batches" '
          def ts: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
          def metric($name; $type; $help; $samples):
            if ($samples | length) == 0 then empty else
              "# HELP insight_driver_\($name) \($help)",
              "# TYPE insight_driver_\($name) \($type)",
              ($samples[] | "insight_driver_\($name)\(.[0]) \(.[1])")
            end;
          def gauge($name; $help; $v):
            if $v == null then empty else metric($name; "gauge"; $help; [["", $v]]) end;
          ($batches | last) as $last |
          gauge("gate_timestamp_seconds"; "When the gate last decided."; $gate.at),
          gauge("gate_go"; "1 if the last gate check started a batch."; $gate.go),
          gauge("gate_surplus"; "Pool 7-day surplus over even pace at the last check, in account-weeks."; $gate.surplus),
          gauge("gate_five_hour"; "Best usable 5-hour share left at the last check."; $gate.fiveHour),
          gauge("gate_min_surplus"; "The surplus the gate wants."; $gate.minSurplus),
          gauge("gate_min_five_hour"; "The 5-hour share the gate wants."; $gate.minFiveHour),
          gauge("running"; "1 while a run is in progress."; $run.running // 0),
          gauge("run_started_timestamp_seconds"; "Start of the latest run."; $run.startedAt),
          gauge("run_ended_timestamp_seconds"; "End of the latest finished run."; $run.endedAt),
          gauge("run_exit_status"; "Exit status of the latest finished run; 3 means it needs a human."; $run.exitStatus),
          gauge("lifetime_cost_usd"; "Token usage the driver has spent, in dollars."; $driver.lifetimeCostUsd),
          gauge("consecutive_failures"; "Failed or empty batches in a row; 2 stops the driver."; $driver.consecutiveFailures),
          metric("batches_total"; "counter"; "Batches recorded, by outcome.";
            [$batches | group_by(.outcome)[] | ["{outcome=\"\(.[0].outcome)\"}", length]]),
          if $last == null then empty else
            gauge("last_batch"; "Number of the latest recorded batch."; $last.batch),
            gauge("last_batch_cost_usd"; "Cost of the latest batch."; $last.costUsd),
            gauge("last_batch_duration_seconds"; "Wall clock of the latest batch.";
              ($last.endedAt | ts) - ($last.startedAt | ts)),
            gauge("last_batch_commits"; "Commits in the latest batch."; $last.commits),
            metric("last_batch_abilities_gained"; "gauge"; "Abilities the latest batch made parse.";
              [["{scope=\"all\"}", $last.overall.abilities.gained],
               ["{scope=\"milestone\",milestone=\"\($last.milestone.name)\"}", $last.milestone.abilities.gained]]),
            metric("milestone_abilities"; "gauge"; "Abilities parsed in the current milestone after the latest batch.";
              [["{milestone=\"\($last.milestone.name)\"}", $last.milestone.abilities.after]])
          end
        ' > ${state}/metrics.prom.tmp
        mv ${state}/metrics.prom.tmp ${state}/metrics.prom
      '';
    };

    gate = pkgs.writeShellApplication {
      name = "insight-driver-gate";
      runtimeInputs = [pkgs.curl pkgs.jq pkgs.gawk pkgs.coreutils renderMetrics];
      text = ''
        # ExecCondition: 1 skips this start quietly, anything else would fail it.
        trap 'exit 1' ERR
        q() {
          curl -fsS --max-time 10 "${prometheus}/api/v1/query" --data-urlencode "query=$1" \
            | jq -r '.data.result[0].value[1] // empty'
        }
        age=$(q 'time() - min(cliproxy_quota_last_success_timestamp_seconds)')
        slack=$(q 'sum(cliproxy_quota_remaining_ratio{window="seven_day"} - (cliproxy_quota_reset_timestamp_seconds{window="seven_day"} - time()) / 604800)')
        # A fresh 5-hour window has no reset time yet, so it reads 1 with no surplus to compute.
        five=$(q 'max(cliproxy_quota_remaining_ratio{window="five_hour"} and on(email) (cliproxy_quota_remaining_ratio{window="seven_day"} > 0.05))')
        verdict=$(awk -v age="''${age:-}" -v slack="''${slack:-}" -v five="''${five:-0}" \
          -v minSlack=${toString cfg.minSlack} -v minFive=${toString cfg.minFiveHour} 'BEGIN {
            if (age == "" || slack == "") { print "skip: no quota metrics in prometheus"; exit }
            if (age > 1800) { printf "skip: quota metrics are %ds old\n", age; exit }
            ok = slack >= minSlack && five >= minFive
            printf "%s: 7-day pool surplus %.2f (want %.2f), best 5-hour %.2f (want %.2f)\n",
              ok ? "go" : "skip", slack, minSlack, five, minFive
          }')
        echo "$verdict"
        go=0
        [[ $verdict == go:* ]] && go=1
        jq -n --argjson at "$(date +%s)" --argjson go "$go" \
          --arg surplus "''${slack:-}" --arg five "''${five:-}" \
          --argjson minSurplus ${toString cfg.minSlack} --argjson minFive ${toString cfg.minFiveHour} \
          '{at: $at, go: $go, surplus: ($surplus | tonumber? // null), fiveHour: ($five | tonumber? // null),
            minSurplus: $minSurplus, minFiveHour: $minFive}' > ${state}/gate.json
        insight-driver-metrics
        [ "$go" = 1 ] || exit 1
      '';
    };

    # ExecStartPre/ExecStopPost. stop only closes a run start opened, since
    # systemd may also run ExecStopPost for a start the gate skipped.
    mark = pkgs.writeShellApplication {
      name = "insight-driver-mark";
      runtimeInputs = [pkgs.jq pkgs.coreutils pkgs.systemd renderMetrics];
      text = ''
        run=${state}/run.json
        prev=$(if [ -s "$run" ]; then cat "$run"; else echo '{}'; fi)
        case "$1" in
          start)
            jq --argjson now "$(date +%s)" '. + {running: 1, startedAt: $now}' <<<"$prev" > "$run.tmp" ;;
          stop)
            [ "$(jq -r '.running // 0' <<<"$prev")" = 1 ] || exit 0
            # A signal death sets EXIT_STATUS to its name (TERM); that reads as -1.
            jq --argjson now "$(date +%s)" --arg status "''${EXIT_STATUS:-}" \
              '. + {running: 0, endedAt: $now, exitStatus: ($status | tonumber? // -1)}' <<<"$prev" > "$run.tmp"
            if [ "''${EXIT_CODE:-}" = exited ] && [ "''${EXIT_STATUS:-}" = 3 ]; then
              systemctl --user stop insight-driver.timer
            fi ;;
        esac
        mv "$run.tmp" "$run"
        insight-driver-metrics
      '';
    };

    run = pkgs.writeShellApplication {
      name = "insight-driver-run";
      runtimeInputs = [pkgs.git pkgs.openssh];
      text = ''
        repo=${lib.escapeShellArg cfg.repo}
        wt=${lib.escapeShellArg cfg.worktree}
        branch=${lib.escapeShellArg cfg.branch}
        if [ ! -e "$wt/.git" ]; then
          git -C "$repo" fetch -q origin
          if ! git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
            git -C "$repo" push -q origin "origin/main:refs/heads/$branch"
            git -C "$repo" fetch -q origin "$branch"
          fi
          git -C "$repo" worktree add -B "$branch" "$wt" "origin/$branch"
          git -C "$wt" branch -q --set-upstream-to "origin/$branch"
        fi
        cd "$wt"
        # 75: taking in main changed the driver, which node loaded before the
        # merge; start again so the batch runs main's driver (and devshell).
        # Bounded, in case main keeps moving under it.
        for _ in 1 2 3; do
          status=0
          nix develop --command bash -c '
            pnpm install --frozen-lockfile --silent &&
            exec node crates/vivisurgeons-insight/driver/src/main.ts "$@"' _ \
            --branch "$branch" \
            --state-dir ${lib.escapeShellArg cfg.stateDir} \
            --max-batches 1 \
            --max-cost-usd ${toString cfg.maxCostUsdPerBatch} \
            --claude-path ${config.home.profileDirectory}/bin/claude \
            || status=$?
          [ "$status" = 75 ] || exit "$status"
        done
        exit 75
      '';
    };
  in {
    options.myHomeManager.insight-driver = {
      enable = lib.mkEnableOption "myHomeManager.insight-driver";
      repo = lib.mkOption {
        type = lib.types.str;
        default = "/pool/dev/progress-engine";
        description = "The human's progress-engine checkout; the worktree hangs off it.";
      };
      worktree = lib.mkOption {
        type = lib.types.str;
        default = "/pool/dev/progress-engine-insight";
        description = "The driver's own checkout, created on first run, so it never edits the human's tree.";
      };
      branch = lib.mkOption {
        type = lib.types.str;
        default = "insight";
        description = "Where the driver commits and pushes.";
      };
      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/pool/dev/progress-engine-insight-state";
        description = "The driver's --state-dir. On /pool because every batch keeps ~50MB of snapshots and transcripts.";
      };
      minSlack = lib.mkOption {
        type = lib.types.float;
        default = 0.1;
        description = "Pool-wide 7-day surplus over even pace, in account-weeks, needed to start a batch.";
      };
      minFiveHour = lib.mkOption {
        type = lib.types.float;
        default = 0.5;
        description = "5-hour share some usable account must have left, so a batch doesn't stall mid-writer.";
      };
      maxCostUsdPerBatch = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "--max-cost-usd for each run; batches have cost $13-19.";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.user.services.insight-driver = {
        Unit.Description = "progress-engine insight driver, one batch on spare Claude quota";
        Service = {
          Type = "oneshot";
          ExecCondition = "${gate}/bin/insight-driver-gate";
          ExecStartPre = "${mark}/bin/insight-driver-mark start";
          ExecStart = "${run}/bin/insight-driver-run";
          # Also where a stop that needs a human (exit 3) stops the timer.
          ExecStopPost = "${mark}/bin/insight-driver-mark stop";
          # nix for the devshell, the claude pool wrapper for the agents.
          Environment = ["PATH=/run/current-system/sw/bin:${config.home.profileDirectory}/bin"];
          # A writer gets 3h plus a 20m grace, then fix-up and review. A kill
          # here is safe: state.json resumes the batch at its step next run.
          TimeoutStartSec = "6h";
          Nice = 10;
        };
      };
      systemd.user.timers.insight-driver = {
        Unit.Description = "Offer the insight driver a batch whenever the pool is under pace";
        Timer = {
          OnCalendar = "*:07/30";
          RandomizedDelaySec = "2m";
        };
        Install.WantedBy = ["timers.target"];
      };
    };
  };
}
