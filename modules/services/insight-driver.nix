# progress-engine's insight batches, run unattended on whatever Claude pool
# quota would otherwise go to waste.
#
# A batch is a T3 Code webhook task: one thread that follows progress-engine's
# insight-batch or chancellor-batch skill (`products`), each product in its own
# clone and T3 project so the two run side by side, and every run shows up in
# T3 Code with its transcript. The insight skill calls its driver's
# subcommands for everything a script can decide
# (crates/vivisurgeons-insight/driver/README.md); the chancellor skill gates
# on the replay milestone.
#
# T3 Code can't decide *when* to run, so a timer here checks every 5 minutes
# and starts at most one batch a check, only when the pool is under pace. "Under
# pace" is per window, not in total: an account's 7-day surplus is what's left
# minus the share of the window still to run, so idle nights bank surplus and
# the batches spend only that, never what a busy week of hand-driven work
# needs. The surplus is the account the proxy spends next: cli-proxy-api's
# reset-first unit sends new sessions to the account whose 7-day window
# resets soonest, so that account's surplus is what a batch would use, and
# usage it leaves at its reset is lost. Summed over the pool it went down as
# the expiring account was spent and stopped the batches exactly when quota
# was going to waste. One batch measured 2026-10-13 cost ~0.06 of a
# 7-day window and ~0.4 of a 5-hour one, which is what the defaults leave room
# for.
#
# Every product is skipped while /tmp, the T3 data dir or a clone has less
# than minFreeGiB free. A product is skipped while T3 Code lists a live thread in its clone's
# project (a batch runs for hours; the webhook would happily start a second
# writer in the same checkout), Insight while its driver is stopped for a
# human, and any product whose last three batches started within 30 minutes
# (they are dying at once; held 3h from the last start). A product's newest
# thread that failed on a transient API or network error is woken in place
# (at most 3 times, within 6h) instead of starting a new batch over its
# uncommitted work. A
# batch is alive exactly as long as its thread, so there is no timeout: a slow
# batch is never taken for dead, and a dead one is found on the next tick. For
# a stop, read escalations.md in the state dir, then clear it with the
# driver's `resume` subcommand.
#
# insight-driver-clone clones each runner checkout that is missing, before
# t3code-declare registers it as a project. Batches push to main when their
# gates pass; there is no branch to merge.
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
    tasks = config.services.t3code.scheduledTasks;
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
          gauge("gate_surplus"; "7-day surplus over even pace of the account spent next, at the last check, in account-weeks."; $gate.surplus),
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

    # Each product's clone and the webhook that starts one of its batches.
    checkouts = {
      insight = cfg.checkout;
      chancellor = cfg.chancellorCheckout;
    };
    webhooks = {
      insight = tasks.insight.webhookUrlFile;
      chancellor = tasks.chancellor.webhookUrlFile;
    };

    clone = pkgs.writeShellApplication {
      name = "insight-driver-clone";
      runtimeInputs = [pkgs.git pkgs.openssh];
      text = lib.concatMapStrings (c: ''
        [ -e ${lib.escapeShellArg c}/.git ] || git clone -q ${lib.escapeShellArg cfg.remote} ${lib.escapeShellArg c}
      '') (lib.attrValues checkouts);
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

        # A product may start a batch when nothing holds it back: Insight's
        # driver stopped for a human, or a live thread in its own clone (a
        # batch runs for hours; its webhook would happily start a second
        # writer there). The thread exists from the webhook's request on, so
        # this also covers a batch that hasn't reached its first step. Same
        # liveness rule as the driver's (src/t3.ts): top-level threads only.
        # A batch on a full disk dies mid-turn: on 2026-11-28 / filled up (61G
        # of VM images), every shell call failed and the overseer couldn't even
        # release its lock. The T3 data dir and /tmp live on /, the clones on
        # /pool; a release build plus snapshots wants a few GiB of each.
        for fs in /tmp ${lib.escapeShellArg config.services.t3code.dataDir} ${lib.escapeShellArgs (lib.attrValues checkouts)}; do
          [ -e "$fs" ] || continue
          free=$(df --output=avail -k "$fs" | tail -n 1 | tr -d ' ')
          if [ "$free" -lt ${toString (cfg.minFreeGiB * 1024 * 1024)} ]; then
            decide "skip: $((free / 1024)) MiB free on $fs (want ${toString cfg.minFreeGiB} GiB)"
          fi
        done

        candidates=()
        busy=()
        for product in ${lib.escapeShellArgs cfg.products}; do
          if [ "$product" = insight ] && [ -s ${state} ]; then
            stopped=$(jq -r '.stopped.reason // empty' ${state})
            if [ -n "$stopped" ]; then
              busy+=("insight stopped for a human ($stopped); see escalations.md, then resume")
              continue
            fi
          fi
          case "$product" in
            ${lib.concatStrings (lib.mapAttrsToList (n: c: ''
            ${n}) checkout=${lib.escapeShellArg c} ;;
            '') checkouts)}
          esac
          # The listing fails now and then and passes on the next try (three
          # misses in two hours on 2026-11-25, fifteen straight passes by hand
          # right after), so a miss is retried before it costs the slot.
          threads=""
          for try in 1 2 3; do
            threads=$(${t3} thread list --base-dir ${lib.escapeShellArg config.services.t3code.dataDir} \
              --project "$checkout" --json) && break
            echo "thread list failed (try $try)" >&2
            threads=""
            sleep 10
          done
          [ -n "$threads" ] || decide "skip: could not list T3 Code threads"
          live=$(jq -r '[.[] | select(.parentThreadId == null)
            | select((.status | IN("preparing", "queued", "starting", "running", "waiting"))
                     or (.pendingBackgroundTasks | length) > 0) | .title] | join(", ")' <<<"$threads")
          # A batch runs ~2h and a live thread blocks the next start, so three
          # starts within 30 minutes are three threads that ended at once:
          # something in the clone makes every batch give up. On 2026-11-24 a
          # dirty tree left by a dead batch did that 45 times in six hours.
          # Hold the product 3h from the last start; it clears by itself, and
          # the overseer sees the verdict in the gate log.
          stalled=$(jq -r --argjson now "$(date +%s)" '
            [.[] | select(.parentThreadId == null) | .createdAt | sub("\\.[0-9]+Z$"; "Z") | fromdate]
            | sort | reverse
            | if length >= 3 and .[0] - .[2] < 1800 and $now - .[0] < 10800
              then "3 batches started within \((.[0] - .[2]) / 60 | floor) min, the last \(($now - .[0]) / 60 | floor) min ago"
              else empty end' <<<"$threads")
          # A batch whose turn died on a network blip (c23 on 2026-11-25, DNS
          # EAI_AGAIN mid-write) leaves its work uncommitted in the clone, and
          # a fresh batch would adopt that tree without knowing what it was.
          # Waking the dead thread keeps its context. Only the newest thread,
          # only a transient error, at most 3 wakes (runCount), within 6h.
          dead=$(jq -r --argjson now "$(date +%s)" '
            [.[] | select(.parentThreadId == null)] | sort_by(.createdAt) | last // empty
            | select(.status == "failed"
                     and $now - (.updatedAt | sub("\\.[0-9]+Z$"; "Z") | fromdate) < 21600)
            | .threadId' <<<"$threads")
          if [ -z "$live" ] && [ -n "$dead" ] \
            && ${t3} thread show --base-dir ${lib.escapeShellArg config.services.t3code.dataDir} \
                 "$dead" --messages 1 --json \
               | jq -e '.thread.runCount < 4 and (.messages[-1].text // "" | test("Can.t reach the API server|EAI_AGAIN|ECONNRESET|ETIMEDOUT|socket hang up|overloaded_error|API Error: 5[0-9][0-9]"))' >/dev/null; then
            ${t3} thread send --base-dir ${lib.escapeShellArg config.services.t3code.dataDir} "$dead" \
              "Your turn died on a transient API or network error; it's back. Your work is as you left it in the tree. Carry on from where you were." >/dev/null \
              && live="woken after a transient API error"
          fi
          if [ -n "$live" ]; then busy+=("$product live ($live)")
          elif [ -n "$stalled" ]; then busy+=("$product stalling ($stalled); read its latest thread")
          else candidates+=("$product"); fi
        done
        if [ "''${#candidates[@]}" -eq 0 ]; then
          decide "skip: nothing free: $(IFS=';'; echo "''${busy[*]}")"
        fi

        q() {
          curl -fsS --max-time 10 "${prometheus}/api/v1/query" --data-urlencode "query=$1" \
            | jq -r '.data.result[0].value[1] // empty'
        }
        age=$(q 'time() - min(cliproxy_quota_last_success_timestamp_seconds)') || age=""
        # The account reset-first routes to: soonest 7-day reset with any left.
        next='bottomk(1, cliproxy_quota_reset_timestamp_seconds{window="seven_day"} and on(email) (cliproxy_quota_remaining_ratio{window="seven_day"} > 0.05))'
        slack=$(q "sum((cliproxy_quota_remaining_ratio{window=\"seven_day\"} - (cliproxy_quota_reset_timestamp_seconds{window=\"seven_day\"} - time()) / 604800) and on(email) $next)") || slack=""
        # A fresh 5-hour window has no reset time yet, so it reads 1 with no surplus to compute.
        five=$(q "max(cliproxy_quota_remaining_ratio{window=\"five_hour\"} and on(email) $next)") || five=""
        decide "$(awk -v age="$age" -v slack="$slack" -v five="''${five:-0}" \
          -v minSlack=${toString cfg.minSlack} -v minFive=${toString cfg.minFiveHour} 'BEGIN {
            if (age == "" || slack == "") { print "skip: no quota metrics in prometheus"; exit }
            if (age > 1800) { printf "skip: quota metrics are %ds old\n", age; exit }
            ok = slack >= minSlack && five >= minFive
            printf "%s: next account 7-day surplus %.2f (want %.2f), best 5-hour %.2f (want %.2f)\n",
              ok ? "go" : "skip", slack, minSlack, five, minFive
          }')"
        # One new batch a tick, so the next start reads quota that counts this
        # one. Round robin over the free products, from the one after the last
        # offered, so a product that frees up often can't starve the other.
        last=$(cat ${dir}/gate-last-product 2>/dev/null || true)
        next=""
        for i in "''${!candidates[@]}"; do
          if [ "''${candidates[$i]}" = "$last" ]; then
            next=''${candidates[$(( (i + 1) % ''${#candidates[@]} ))]}
          fi
        done
        next=''${next:-''${candidates[0]}}
        case "$next" in
          ${lib.concatStrings (lib.mapAttrsToList (n: w: ''
          ${n}) url=$(cat ${lib.escapeShellArg w}) ;;
          '') webhooks)}
        esac
        mkdir -p ${lib.escapeShellArg cfg.chancellorStateDir}/batches
        echo "offering a $next batch"
        echo "$next" > ${dir}/gate-last-product
        curl -fsS --max-time 30 -X POST "$url"
        echo
      '';
    };
  in {
    options.myNixOS.services.insight-driver = {
      enable = lib.mkEnableOption "myNixOS.services.insight-driver";
      remote = lib.mkOption {
        type = lib.types.str;
        default = "git@github.com:cramt/progress-engine.git";
        description = "Where the runner clones progress-engine from and pushes its batches to (main).";
      };
      checkout = lib.mkOption {
        type = lib.types.str;
        default = "/pool/dev/progress-engine-insight";
        description = ''
          The runner's clone for Insight batches, on main, and its T3 Code
          project. A clone, not a worktree of the human's checkout: a worktree
          can't have main checked out twice.
        '';
      };
      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/pool/dev/progress-engine-insight-state";
        description = "The driver's --state-dir. On /pool because every batch keeps ~50MB of snapshots and transcripts.";
      };
      products = lib.mkOption {
        type = lib.types.nonEmptyListOf (lib.types.enum ["insight" "chancellor"]);
        default = ["insight" "chancellor"];
        description = ''
          What the runner works on, each in its own clone at the same time:
          Insight's grammar (the insight-batch skill) and Chancellor's replay
          milestone (the chancellor-batch skill). The gate starts at most one
          batch a tick, taking the free products in turn.
        '';
      };
      chancellorCheckout = lib.mkOption {
        type = lib.types.str;
        default = "/pool/dev/progress-engine-chancellor";
        description = "The runner's clone for Chancellor batches, on main, and its T3 Code project, so a Chancellor batch runs beside an Insight one.";
      };
      chancellorStateDir = lib.mkOption {
        type = lib.types.str;
        default = "/pool/dev/progress-engine-chancellor-state";
        description = "The chancellor batches' state dir: batches/<n>/ baselines and the handoff.";
      };
      minFreeGiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5;
        description = "Free space, in GiB, a batch needs on /tmp, the T3 data dir and its clone before one starts.";
      };
      minSlack = lib.mkOption {
        type = lib.types.float;
        default = 0.1;
        description = "7-day surplus over even pace of the account the proxy spends next (soonest reset), in account-weeks, needed to start a batch.";
      };
      minFiveHour = lib.mkOption {
        type = lib.types.float;
        default = 0.5;
        description = "5-hour share some usable account must have left, so a batch doesn't stall mid-writer.";
      };
    };

    config = lib.mkIf cfg.enable {
      services.t3code = {
        projects.progress-engine-insight.workspaceRoot = cfg.checkout;
        projects.progress-engine-chancellor.workspaceRoot = cfg.chancellorCheckout;
        scheduledTasks.insight = {
          title = "insight batch";
          project = cfg.checkout;
          schedule.webhook = {};
          model.model = "claude-opus-5-5";
          prompt = ''
            Run one insight batch with the insight-batch skill, state dir
            ${cfg.stateDir}.
          '';
        };
        scheduledTasks.chancellor = {
          title = "chancellor batch";
          project = cfg.chancellorCheckout;
          schedule.webhook = {};
          model.model = "claude-opus-5-5";
          prompt = ''
            Run one chancellor batch with the chancellor-batch skill, state dir
            ${cfg.chancellorStateDir}.
          '';
        };
      };

      systemd.user.services.insight-driver-clone = {
        description = "Clone each runner checkout that is missing";
        before = ["t3code-declare.service"];
        wantedBy = ["t3code-declare.service"];
        unitConfig.ConditionUser = config.services.t3code.user;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe clone;
        };
      };

      systemd.user.services.insight-driver-gate = {
        description = "Offer an insight batch to T3 Code if the Claude pool is under pace";
        wants = ["insight-driver-clone.service"];
        after = ["insight-driver-clone.service"];
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
          # A skip costs a few seconds; a batch that ends waits at most this
          # long for the next. 30 minutes left ~15 idle minutes per batch.
          OnCalendar = "*:0/5";
          RandomizedDelaySec = "30s";
        };
      };
    };
  };
}
