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
{ ... }: {
  hmModules.features.insight-driver = { config, lib, pkgs, osConfig, ... }: let
    cfg = config.myHomeManager.insight-driver;
    prometheus = "http://127.0.0.1:${toString osConfig.port-selector.ports.prometheus}";

    gate = pkgs.writeShellApplication {
      name = "insight-driver-gate";
      runtimeInputs = [pkgs.curl pkgs.jq pkgs.gawk];
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
        if [ -z "$age" ] || [ -z "$slack" ]; then
          echo "skip: no quota metrics in prometheus"
          exit 1
        fi
        awk -v age="$age" -v slack="$slack" -v five="''${five:-0}" \
          -v minSlack=${toString cfg.minSlack} -v minFive=${toString cfg.minFiveHour} 'BEGIN {
            if (age > 1800) { printf "skip: quota metrics are %ds old\n", age; exit 1 }
            ok = slack >= minSlack && five >= minFive
            printf "%s: 7-day pool surplus %.2f (want %.2f), best 5-hour %.2f (want %.2f)\n",
              ok ? "go" : "skip", slack, minSlack, five, minFive
            exit !ok
          }'
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
        exec nix develop --command bash -c '
          pnpm install --frozen-lockfile --silent &&
          exec node crates/vivisurgeons-insight/driver/src/main.ts "$@"' _ \
          --branch "$branch" \
          --state-dir ${lib.escapeShellArg cfg.stateDir} \
          --max-batches 1 \
          --max-cost-usd ${toString cfg.maxCostUsdPerBatch} \
          --claude-path ${config.home.profileDirectory}/bin/claude
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
          ExecStart = "${run}/bin/insight-driver-run";
          ExecStopPost = toString (pkgs.writeShellScript "insight-driver-needs-human" ''
            if [ "$EXIT_CODE" = exited ] && [ "$EXIT_STATUS" = 3 ]; then
              ${pkgs.systemd}/bin/systemctl --user stop insight-driver.timer
            fi
          '');
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
