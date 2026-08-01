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
# alongside) for the exact commands.
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
    configFile = "${authDir}/config.yaml";

    settings = {
      host = "127.0.0.1";
      inherit (cfg) port;
      tls.enable = false;
      auth-dir = authDir;
      debug = false;

      # Management API is disabled outright (empty secret-key => 404 on every
      # /v0/management route), which also stops the bundled control panel from
      # being downloaded from GitHub at runtime.
      remote-management = {
        allow-remote = false;
        secret-key = "";
        disable-control-panel = true;
      };

      routing = {
        inherit (cfg) strategy;
        session-affinity = cfg.session-affinity;
      };
    };

    # Everything except api-keys is declarative; the key is spliced in at start.
    baseConfig = (pkgs.formats.yaml {}).generate "cli-proxy-api-base.yaml" settings;

    startScript = pkgs.writeShellScript "cli-proxy-api-start" ''
      set -euo pipefail
      mkdir -p ${lib.escapeShellArg authDir}
      chmod 700 ${lib.escapeShellArg authDir}

      if [ ! -s ${lib.escapeShellArg keyFile} ]; then
        ${lib.getExe pkgs.openssl} rand -hex 32 > ${lib.escapeShellArg keyFile}
        chmod 600 ${lib.escapeShellArg keyFile}
      fi

      umask 077
      {
        cat ${baseConfig}
        printf 'api-keys:\n  - "%s"\n' "$(cat ${lib.escapeShellArg keyFile})"
      } > ${lib.escapeShellArg configFile}

      exec ${lib.getExe cliProxyPkg} -config ${lib.escapeShellArg configFile}
    '';

    # Login helper. Each invocation is one OAuth consent in a browser; run it
    # once per account. The proxy must be stopped first — it holds auth-dir.
    accountsHelper = pkgs.writeShellScriptBin "agent-accounts" ''
      set -euo pipefail
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
        *)
          echo "usage: agent-accounts [list|add [claude|antigravity|codex|kimi|xai]]" >&2
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
