# progress-engine's insight batches, run unattended on whatever Claude pool
# quota would otherwise go to waste.
#
# A batch is a T3 Code webhook task: one thread that follows progress-engine's
# insight-batch skill in the driver worktree, so every run shows up in T3 Code
# with its transcript. The skill calls the driver's subcommands for everything
# a script can decide (baseline, gates, push or park, triage); see
# crates/vivisurgeons-insight/driver/README.md.
#
# T3 Code can't decide *when* to run, so a timer here offers a batch every
# 30 minutes and only calls the webhook when the pool is under pace. "Under
# pace" is per window, not in total: an account's 7-day surplus is what's left
# minus the share of the window still to run, so idle nights bank surplus and
# the batches spend only that, never what a busy week of hand-driven work
# needs. The surplus is summed over the pool because an exhausted account's
# demand spills onto the others. One batch measured 2026-10-13 cost ~0.06 of a
# 7-day window and ~0.4 of a 5-hour one, which is what the defaults leave room
# for.
#
# The gate also skips while T3 Code lists a live thread in the worktree's
# project (a batch runs for hours; the webhook would happily start a second
# writer in the same checkout) or while the driver is stopped for a human. A
# batch is alive exactly as long as its thread, so there is no timeout: a slow
# batch is never taken for dead, and a dead one is found on the next tick. For
# a stop, read escalations.md in the state dir, then clear it with the
# driver's `resume` subcommand.
#
# insight-driver-worktree makes the worktree (`insight` branch) when it is
# missing, before t3code-declare registers it as a project. Merge `insight`
# into main (merge or fast-forward, never squash) to take its work.
#
# Every gate check also rebuilds <stateDir>/metrics.prom (insight_driver_*)
# from its own verdict and the driver's files, for the Insight driver
# dashboard; luna links it into node_exporter with metrics.textfiles. It never
# blocks a batch: an oversized --argjson once failed the render and, through
# an ERR trap, silently skipped every batch for two weeks.
{...}: {
  flake.nixosModules."services.insight-driver" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.insight-driver;
    task = config.services.t3code.scheduledTasks.insight;
    prometheus = "http://127.0.0.1:${toString config.port-selector.ports.prometheus}";
    t3 = lib.getExe' config.services.t3code.package "t3";
    dir = lib.escapeShellArg cfg.stateDir;
    state = lib.escapeShellArg "${cfg.stateDir}/state.json";

    # metrics.prom, rebuilt whole from the gate's last verdict and the
    # driver's own files, so no producer has to edit another's lines.
    renderMetrics = pkgs.writeShellApplication {
      name = "insight-driver-metrics";
      runtimeInputs = [pkgs.jq pkgs.coreutils];
      text = ''
        json() { if [ -s "$1" ]; then cat "$1"; else echo null; fi; }
        # Files, not arguments: metrics.jsonl grows every batch, and one
        # argument may not exceed 128KiB (E2BIG).
        jq -nr \
          --slurpfile gate <(json ${dir}/gate.json) \
          --slurpfile driver <(json ${dir}/state.json) \
          --slurpfile lines <(cat ${dir}/metrics.jsonl 2>/dev/null || true) '
          $gate[0] as $gate | $driver[0] as $driver |
          ($lines | map(select(.batch))) as $batches |
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
          gauge("running"; "1 while a batch is in flight, as of the last gate check."; if $driver.inFlight then 1 else 0 end),
          gauge("stopped"; "1 while the driver waits for a human."; if $driver.stopped then 1 else 0 end),
          gauge("consecutive_failures"; "Failed or empty batches in a row; 2 stops the driver."; $driver.consecutiveFailures),
          metric("batches_total"; "counter"; "Batches recorded, by outcome.";
            [$batches | group_by(.outcome)[] | ["{outcome=\"\(.[0].outcome)\"}", length]]),
          if $last == null then empty else
            gauge("last_batch"; "Number of the latest recorded batch."; $last.batch),
            gauge("last_batch_duration_seconds"; "Wall clock of the latest batch.";
              ($last.endedAt | ts) - ($last.startedAt | ts)),
            gauge("last_batch_commits"; "Commits in the latest batch."; $last.commits),
            metric("last_batch_abilities_gained"; "gauge"; "Abilities the latest batch made parse.";
              [["{scope=\"all\"}", $last.overall.abilities.gained],
               ["{scope=\"milestone\",milestone=\"\($last.milestone.name)\"}", $last.milestone.abilities.gained]]),
            metric("milestone_abilities"; "gauge"; "Abilities parsed in the current milestone after the latest batch.";
              [["{milestone=\"\($last.milestone.name)\"}", $last.milestone.abilities.after]])
          end
        ' > ${dir}/metrics.prom.tmp
        mv ${dir}/metrics.prom.tmp ${dir}/metrics.prom
      '';
    };

    worktree = pkgs.writeShellApplication {
      name = "insight-driver-worktree";
      runtimeInputs = [pkgs.git pkgs.openssh];
      text = ''
        repo=${lib.escapeShellArg cfg.repo}
        git -C "$repo" fetch -q origin
        if ! git -C "$repo" rev-parse -q --verify refs/remotes/origin/insight >/dev/null; then
          git -C "$repo" push -q origin origin/main:refs/heads/insight
          git -C "$repo" fetch -q origin insight
        fi
        # A worktree deleted without `git worktree remove` still holds the branch.
        git -C "$repo" worktree prune
        git -C "$repo" worktree add -B insight ${lib.escapeShellArg cfg.worktree} origin/insight
        git -C ${lib.escapeShellArg cfg.worktree} branch -q --set-upstream-to origin/insight
      '';
    };

    gate = pkgs.writeShellApplication {
      name = "insight-driver-gate";
      runtimeInputs = [pkgs.curl pkgs.jq pkgs.gawk pkgs.coreutils renderMetrics];
      text = ''
        slack="" five=""
        # Every verdict, skip or go, is recorded and rendered for the dashboard.
        decide() {
          echo "$1"
          go=0
          [[ $1 == go:* ]] && go=1
          jq -n --argjson at "$(date +%s)" --argjson go "$go" \
            --arg surplus "$slack" --arg five "$five" \
            --argjson minSurplus ${toString cfg.minSlack} --argjson minFive ${toString cfg.minFiveHour} \
            '{at: $at, go: $go, surplus: ($surplus | tonumber? // null), fiveHour: ($five | tonumber? // null),
              minSurplus: $minSurplus, minFiveHour: $minFive}' > ${dir}/gate.json \
            || echo "could not write gate.json" >&2
          insight-driver-metrics || echo "insight-driver-metrics failed" >&2
          [ "$go" = 1 ] || exit 0
        }

        if [ -s ${state} ]; then
          stopped=$(jq -r '.stopped.reason // empty' ${state})
          [ -z "$stopped" ] || decide "skip: stopped for a human ($stopped); see escalations.md, then resume"
        fi

        # The thread exists from the webhook's request on, so this also covers
        # a batch that hasn't reached `start` yet. A claim in state.json left by
        # a dead thread doesn't block: the next batch's `start` recovers it.
        # Same rule as the driver's (src/t3.ts): top-level threads only.
        threads=$(${t3} thread list --base-dir ${lib.escapeShellArg config.services.t3code.dataDir} \
          --project ${lib.escapeShellArg cfg.worktree} --json) \
          || decide "skip: could not list T3 Code threads"
        live=$(jq -r '[.[] | select(.parentThreadId == null)
          | select((.status | IN("preparing", "queued", "starting", "running", "waiting"))
                   or (.pendingBackgroundTasks | length) > 0) | .title] | join(", ")' <<<"$threads")
        [ -z "$live" ] || decide "skip: a batch thread is live ($live)"

        q() {
          curl -fsS --max-time 10 "${prometheus}/api/v1/query" --data-urlencode "query=$1" \
            | jq -r '.data.result[0].value[1] // empty'
        }
        age=$(q 'time() - min(cliproxy_quota_last_success_timestamp_seconds)') || age=""
        slack=$(q 'sum(cliproxy_quota_remaining_ratio{window="seven_day"} - (cliproxy_quota_reset_timestamp_seconds{window="seven_day"} - time()) / 604800)') || slack=""
        # A fresh 5-hour window has no reset time yet, so it reads 1 with no surplus to compute.
        five=$(q 'max(cliproxy_quota_remaining_ratio{window="five_hour"} and on(email) (cliproxy_quota_remaining_ratio{window="seven_day"} > 0.05))') || five=""
        decide "$(awk -v age="$age" -v slack="$slack" -v five="''${five:-0}" \
          -v minSlack=${toString cfg.minSlack} -v minFive=${toString cfg.minFiveHour} 'BEGIN {
            if (age == "" || slack == "") { print "skip: no quota metrics in prometheus"; exit }
            if (age > 1800) { printf "skip: quota metrics are %ds old\n", age; exit }
            ok = slack >= minSlack && five >= minFive
            printf "%s: 7-day pool surplus %.2f (want %.2f), best 5-hour %.2f (want %.2f)\n",
              ok ? "go" : "skip", slack, minSlack, five, minFive
          }')"
        curl -fsS --max-time 30 -X POST "$(cat ${lib.escapeShellArg task.webhookUrlFile})"
        echo
      '';
    };
  in {
    options.myNixOS.services.insight-driver = {
      enable = lib.mkEnableOption "myNixOS.services.insight-driver";
      repo = lib.mkOption {
        type = lib.types.str;
        default = "/pool/dev/progress-engine";
        description = "The human's progress-engine checkout; the worktree hangs off it.";
      };
      worktree = lib.mkOption {
        type = lib.types.str;
        default = "/pool/dev/progress-engine-insight";
        description = "The driver's checkout of the `insight` branch, and the T3 Code project the batches run in.";
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
    };

    config = lib.mkIf cfg.enable {
      services.t3code = {
        projects.progress-engine-insight.workspaceRoot = cfg.worktree;
        scheduledTasks.insight = {
          title = "insight batch";
          project = cfg.worktree;
          schedule.webhook = {};
          model.model = "claude-opus-5-5";
          prompt = ''
            Run one insight batch with the insight-batch skill, state dir
            ${cfg.stateDir}.
          '';
        };
      };

      systemd.user.services.insight-driver-worktree = {
        description = "Make the insight driver's worktree if it is missing";
        before = ["t3code-declare.service"];
        wantedBy = ["t3code-declare.service"];
        unitConfig = {
          ConditionUser = config.services.t3code.user;
          ConditionPathExists = "!${cfg.worktree}/.git";
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe worktree;
        };
      };

      systemd.user.services.insight-driver-gate = {
        description = "Offer an insight batch to T3 Code if the Claude pool is under pace";
        wants = ["insight-driver-worktree.service"];
        after = ["insight-driver-worktree.service"];
        unitConfig.ConditionUser = config.services.t3code.user;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe gate;
        };
      };
      systemd.user.timers.insight-driver-gate = {
        description = "Offer an insight batch whenever the pool is under pace";
        wantedBy = ["timers.target"];
        unitConfig.ConditionUser = config.services.t3code.user;
        timerConfig = {
          OnCalendar = "*:07/30";
          RandomizedDelaySec = "2m";
        };
      };
    };
  };
}
