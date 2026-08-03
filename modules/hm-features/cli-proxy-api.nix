# CLIProxyAPI — pools several Claude subscription accounts behind one
# Anthropic-compatible endpoint on localhost, with per-model 429 cooldown and
# automatic failover when the bound account is exhausted. Consumed by the
# `claude` wrapper in modules/hm-features/claude-code.nix.
#
# This is a *home-manager* module, not modules/services/, on purpose: the
# credentials are per-user OAuth tokens created by an interactive browser flow
# (`cli-proxy-api -claude-login`) and live in auth-dir. A system service under
# DynamicUser would put them somewhere the login flow can't reach.
#
# Adding accounts is a manual one-time step per account — Nix can declare the
# config but cannot perform an OAuth consent. See `agent-accounts` (installed
# alongside) for the exact commands; it also has `usage` (per-account request
# counts and cooldowns) and `ui` (upstream's management TUI).
#
# Anything changed through the TUI is ephemeral: config.yaml is rebuilt from
# this module on every service start.
{inputs, ...}: {
  hmModules.features.cli-proxy-api = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.cli-proxy-api;

    cliProxyPkg = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.cli-proxy-api;

    authDir = "${config.home.homeDirectory}/.cli-proxy-api";
    # The local API key gates 127.0.0.1 only, but the nix store is world
    # readable while the OAuth tokens next to it are 0600 — putting the key in
    # the store would make it the weakest link. Generated once on first start
    # instead. `api-keys` takes a literal list with no env expansion (checked
    # against config.example.yaml in 7.2.113), so the config file is assembled
    # at start rather than being a pure store path.
    keyFile = "${authDir}/local-api-key";
    # Same reasoning for the management key: it gates /v0/management, which can
    # read the config (including the api key) and delete credentials. The server
    # bcrypt-hashes it in memory and never persists the hash back, so the
    # plaintext here stays the only copy.
    mgmtKeyFile = "${authDir}/management-key";
    configFile = "${authDir}/config.yaml";

    # Upstream's web control panel, pinned as the cli-proxy-api-panel flake
    # input so the server never fetches it from GitHub at runtime.
    # MANAGEMENT_STATIC_PATH wants either a file literally named
    # management.html or a directory containing one, and a file input lands in
    # the store as "source" — hence the directory.
    managementPanel = pkgs.runCommand "cli-proxy-api-panel" {} ''
      mkdir -p $out
      ln -s ${inputs.cli-proxy-api-panel} $out/management.html
    '';

    settings = {
      host = "127.0.0.1";
      inherit (cfg) port;
      tls.enable = false;
      auth-dir = authDir;
      debug = false;

      routing = {
        inherit (cfg) strategy;
        session-affinity = cfg.session-affinity;
      };
    };

    # Everything except the two generated keys is declarative; they are spliced
    # in at start. remote-management lives in the same splice because YAML
    # rejects a duplicate top-level key.
    baseConfig = (pkgs.formats.yaml {}).generate "cli-proxy-api-base.yaml" settings;

    startScript = pkgs.writeShellScript "cli-proxy-api-start" ''
      set -euo pipefail
      mkdir -p ${lib.escapeShellArg authDir}
      chmod 700 ${lib.escapeShellArg authDir}

      gen_key() {
        if [ ! -s "$1" ]; then
          ${lib.getExe pkgs.openssl} rand -hex 32 > "$1"
          chmod 600 "$1"
        fi
      }
      gen_key ${lib.escapeShellArg keyFile}
      gen_key ${lib.escapeShellArg mgmtKeyFile}

      umask 077
      {
        cat ${baseConfig}
        printf 'api-keys:\n  - "%s"\n' "$(cat ${lib.escapeShellArg keyFile})"
        # Management API and control panel are localhost-only and gated by their
        # own key. Auto-update is off because the panel comes from the store.
        printf 'remote-management:\n  allow-remote: false\n  disable-control-panel: false\n  disable-auto-update-panel: true\n  secret-key: "%s"\n' \
          "$(cat ${lib.escapeShellArg mgmtKeyFile})"
      } > ${lib.escapeShellArg configFile}

      export MANAGEMENT_STATIC_PATH=${managementPanel}
      exec ${lib.getExe cliProxyPkg} -config ${lib.escapeShellArg configFile}
    '';

    # Login helper. Each invocation is one OAuth consent in a browser; run it
    # once per account. The proxy must be stopped first — it holds auth-dir.
    accountsHelper = pkgs.writeShellScriptBin "agent-accounts" ''
      set -euo pipefail

      api="http://127.0.0.1:${toString cfg.port}/v0/management"

      mgmt_api() {
        ${lib.getExe pkgs.curl} -fsS --max-time 20 \
          -H "Authorization: Bearer $(cat ${lib.escapeShellArg mgmtKeyFile})" "$@"
      }

      # "2026-08-03T11:29:59Z" -> "2h13m", because a wall-clock timestamp needs
      # arithmetic to be useful and this column is read at a glance.
      relative_time() {
        local target now delta
        case "''${1:-}" in "" | "-" | "?") echo "-" ; return ;; esac
        target=$(date -d "$1" +%s 2>/dev/null) || { echo "-"; return; }
        now=$(date +%s)
        delta=$((target - now))
        if [ "$delta" -le 0 ]; then
          echo "now"
        else
          printf '%dh%02dm\n' "$((delta / 3600))" "$(((delta % 3600) / 60))"
        fi
      }

      case "''${1:-list}" in
        add)
          # Provider decides which upstream the credential talks to. Note that
          # non-claude providers serve their own model ids (antigravity =>
          # gemini-*), so reaching them from Claude Code needs ANTHROPIC_MODEL
          # set to one of those — the pool does not alias them onto claude-*.
          case "''${2:-claude}" in
            claude) loginFlag=-claude-login ;;
            antigravity) loginFlag=-antigravity-login ;;
            codex) loginFlag=-codex-login ;;
            kimi) loginFlag=-kimi-login ;;
            xai) loginFlag=-xai-login ;;
            *)
              echo "unknown provider: $2 (claude|antigravity|codex|kimi|xai)" >&2
              exit 2
              ;;
          esac
          systemctl --user stop cli-proxy-api
          ${lib.getExe cliProxyPkg} -config ${lib.escapeShellArg configFile} "$loginFlag"
          systemctl --user start cli-proxy-api
          ;;
        list)
          echo "accounts in ${authDir}:"
          find ${lib.escapeShellArg authDir} -maxdepth 1 -name '*.json' -printf '  %f\n' 2>/dev/null || true
          ;;
        usage)
          # SESSION/WEEK are Anthropic's own subscription counters, the same
          # numbers /usage shows in Claude Code. They are not in the proxy's
          # data model: /api-call re-issues an arbitrary request with the
          # credential's live access token substituted for $TOKEN$, which is
          # also how the web panel gets them. OK/FAIL are the proxy's own
          # counters and reset when the service restarts.
          accounts=$(mgmt_api "$api/auth-files" | ${lib.getExe pkgs.jq} -r '
            def dash: if . == null or . == "" then "-" else . end;
            .files[] | [
              (.auth_index | dash),
              ((.email // .name) | dash),
              (.provider | dash),
              (if .disabled then "disabled" elif .unavailable then "unavailable" else (.status | dash) end),
              (.success // 0),
              (.failed // 0),
              (.next_retry_after | dash)
            ] | @tsv')

          {
            printf 'ACCOUNT\tPROVIDER\tSTATUS\tSESSION\tWEEK\tRESETS\tOK\tFAIL\tRETRY-AFTER\n'
            while IFS="$(printf '\t')" read -r idx account provider status ok fail retry; do
              session="-"
              week="-"
              resets="-"
              # Only Claude subscriptions have this endpoint; the other
              # providers stay "-" rather than guessing at an equivalent.
              if [ "$provider" = "claude" ]; then
                quota=$(mgmt_api -X POST "$api/api-call" -H 'Content-Type: application/json' \
                  -d "{\"auth_index\":\"$idx\",\"method\":\"GET\",\"url\":\"https://api.anthropic.com/api/oauth/usage\",\"header\":{\"Authorization\":\"Bearer \$TOKEN\$\",\"anthropic-beta\":\"oauth-2025-04-20\"}}" || echo "")
                IFS="$(printf '\t')" read -r session week resetsAt < <(
                  printf '%s' "$quota" | ${lib.getExe pkgs.jq} -r '
                    if .status_code == 200 then (.body | fromjson) else null end
                    | if . == null then ["?", "?", "-"] else
                        [ "\(.five_hour.utilization // 0 | round)%",
                          "\(.seven_day.utilization // 0 | round)%",
                          (.five_hour.resets_at // "-") ]
                      end | @tsv' 2>/dev/null || printf '?\t?\t-\n'
                )
                resets=$(relative_time "$resetsAt")
              fi
              printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$account" "$provider" "$status" "$session" "$week" "$resets" "$ok" "$fail" "$retry"
            done <<< "$accounts"
          } | ${pkgs.util-linux}/bin/column -t -s "$(printf '\t')"
          ;;
        dashboard | panel)
          # Upstream's web panel. It asks for the management key on first load
          # and keeps it in browser storage, so the clipboard copy is a one-off.
          ${pkgs.wl-clipboard}/bin/wl-copy < ${lib.escapeShellArg mgmtKeyFile}
          echo "management key copied to clipboard — paste it into the panel"
          exec ${pkgs.xdg-utils}/bin/xdg-open "http://127.0.0.1:${toString cfg.port}/management.html"
          ;;
        ui | tui)
          # Management client against the already-running service. -password is
          # visible in /proc/<pid>/cmdline; acceptable on a single-user box, and
          # the alternative is retyping a 64-char key into the auth gate.
          exec ${lib.getExe cliProxyPkg} -config ${lib.escapeShellArg configFile} \
            -tui -password "$(cat ${lib.escapeShellArg mgmtKeyFile})"
          ;;
        key)
          # For hitting /v0/management by hand, or piping: `... | wl-copy -n`.
          if [ ! -s ${lib.escapeShellArg mgmtKeyFile} ]; then
            echo "no management key yet — the service generates it on first start" >&2
            exit 1
          fi
          cat ${lib.escapeShellArg mgmtKeyFile}
          ;;
        *)
          echo "usage: agent-accounts [list|usage|dashboard|ui|key|add [claude|antigravity|codex|kimi|xai]]" >&2
          exit 2
          ;;
      esac
    '';
  in {
    options.myHomeManager.cli-proxy-api = {
      enable = lib.mkEnableOption "myHomeManager.cli-proxy-api";

      # Not port-selector: that allocator is a NixOS-level option and this is a
      # user service. Upstream's default, bound to loopback.
      port = lib.mkOption {
        type = lib.types.port;
        default = 8317;
        description = "Loopback port for the proxy.";
      };

      strategy = lib.mkOption {
        type = lib.types.enum ["round-robin" "weighted-round-robin" "fill-first"];
        default = "fill-first";
        description = ''
          Credential selection strategy. fill-first drains one account before
          moving to the next, which staggers rolling-window subscription caps —
          round-robin spreads usage so every account hits its window at once.
        '';
      };

      session-affinity = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Pin a conversation to the account it started on, so prompt caching
          survives. Failover to another account is still automatic once the
          bound one is exhausted.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [cliProxyPkg accountsHelper];

      systemd.user.services.cli-proxy-api = {
        Unit = {
          Description = "CLIProxyAPI — pooled Claude accounts behind a local Anthropic-compatible endpoint";
          After = ["network.target"];
        };
        Service = {
          ExecStart = "${startScript}";
          Restart = "always";
          RestartSec = 2;
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}
