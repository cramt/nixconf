{inputs, ...}: {
  hmModules.features.claude-code = {
    config,
    lib,
    pkgs,
    ...
  }: let
    claudeCodePkg = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

    # Skill libraries and helper binaries — see myLib/agent-skills.nix for how
    # each set is enumerated and why.
    skills = import ../../myLib/agent-skills.nix {inherit lib pkgs inputs;};
    agentBrowserPkg = skills.agent-browser;

    # `m365claude`: regular Claude with the Microsoft 365 MCP merged in for that
    # session only (via --mcp-config, which adds to — not replaces — the normal
    # servers). It has to stay out of the always-on servers: all 336 of its tools
    # cost 741K context tokens against a 42K zero-server floor — 74% of the 1M
    # window, gone before the first prompt. `--enabled-tools` is a regex over tool
    # names; measured costs are mail 106K, mail|calendar 170K, +contact 196K, so
    # the default stays at the one surface that has ever actually been called.
    # Benchmark: `claude -p 'say ok' --mcp-config <cfg> --strict-mcp-config`, then
    # read the first request's usage out of the session transcript.
    m365McpConfig = pkgs.writeText "ms365-mcp.json" (builtins.toJSON {
      mcpServers.ms365 = {
        command = "${pkgs.nodejs}/bin/npx";
        args = [
          "-y"
          "@softeria/ms-365-mcp-server"
          "--org-mode"
          "--enabled-tools"
          cfg.ms365.enabledTools
        ];
      };
    });
    m365ClaudePkg = pkgs.writeShellScriptBin "m365claude" ''
      exec ${claudeCodePkg}/bin/claude --mcp-config ${m365McpConfig} "$@"
    '';

    cfg = config.myHomeManager.claude-code;

    # `claude` wrapper: point Claude Code at the cli-proxy-api pool on luna
    # (myLib/claude-pool.nix) so requests are spread over the pooled Claude
    # accounts instead of the single OAuth login in ~/.claude. The proxy
    # authenticates upstream with its own stored tokens, so what Claude Code
    # sends is the pool's api key — ANTHROPIC_API_KEY is cleared so it can't
    # fall back to a real Anthropic key. hiPrio to win over the raw claude-code
    # binary the development bundle installs.
    # Falls back to Claude Code's own OAuth whenever the pool can't be reached
    # (luna down, opnix not rendered yet): silently routing at that point
    # would break `claude` entirely rather than degrade.
    pool = import ../../myLib/claude-pool.nix;
    claudePoolPkg = lib.hiPrio (pkgs.writeShellScriptBin "claude" ''
      keyfile=${pool.apiKeyFile}

      if [ -r "$keyfile" ] && [ -s "$keyfile" ] &&
         timeout 2 bash -c '</dev/tcp/${pool.host}/443' 2>/dev/null; then
        export ANTHROPIC_BASE_URL="${pool.url}"
        export ANTHROPIC_AUTH_TOKEN="$(cat "$keyfile")"
        # Must be empty, not unset: a real key here would let Claude Code bill
        # the API directly instead of going through the pooled subscriptions.
        export ANTHROPIC_API_KEY=""
        # claude.ai cloud connectors need the OAuth login to be the winning
        # auth source, which it never is while we're routing through the pool.
        # Left alone, Claude Code notices that and nags every session; opting
        # out explicitly makes it skip the fetch instead of warning about it.
        export ENABLE_CLAUDEAI_MCP_SERVERS=0
      else
        # Drop any inherited routing so "fallback" really means direct — a
        # stale ANTHROPIC_BASE_URL in the shell (or a nested claude session)
        # would otherwise silently survive into the fallback path. Connectors
        # do work on this path, so the opt-out goes too.
        unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ENABLE_CLAUDEAI_MCP_SERVERS

        if [ ! -r "$keyfile" ]; then
          echo "claude: cannot read $keyfile — using the direct OAuth login." >&2
          echo "        needs myNixOS.opnix-secrets and the onepassword-secrets group (re-login after first deploy)." >&2
        else
          echo "claude: ${pool.host} unreachable — using the direct OAuth login." >&2
        fi
      fi

      exec ${claudeCodePkg}/bin/claude "$@"
    '');

    globalClaudeMd = builtins.readFile ./global-agent-instructions.md;

    # Keys we own inside ~/.claude/settings.json. The file can't be a
    # home.file symlink: Claude Code writes to it itself (/model, /theme), so
    # these get deep-merged in on every activation and everything else in the
    # file is left alone.
    declaredSettings = (pkgs.formats.json {}).generate "claude-declared-settings.json" {
      # Empty string hides the Co-Authored-By trailer / "Generated with"
      # footer entirely. The global instructions already forbid attribution,
      # but the harness injects its own default, so it has to die at the source.
      attribution = {
        commit = "";
        pr = "";
      };
    };
    mergeSettings = pkgs.writeShellApplication {
      name = "claude-merge-settings";
      runtimeInputs = [pkgs.coreutils pkgs.jq];
      text = ''
        f="$HOME/.claude/settings.json"
        install -d "$HOME/.claude"
        # Refuse to clobber a file we can't parse — that's hand-edited state
        # worth more than our two keys.
        if [ -e "$f" ]; then
          current=$(jq . "$f") || { echo "claude-merge-settings: $f is not valid JSON, skipping" >&2; exit 0; }
        else
          current='{}'
        fi
        printf '%s' "$current" | jq --slurpfile declared ${declaredSettings} '. * $declared[0]' > "$f.new"
        mv "$f.new" "$f"
      '';
    };
  in {
    options.myHomeManager.claude-code = {
      enable = lib.mkEnableOption "myHomeManager.claude-code";
      agent-browser.enable =
        lib.mkEnableOption "Vercel agent-browser CLI + Claude Code skill"
        // {default = true;};
      pstack.enable =
        lib.mkEnableOption "vendored pstack judgment skills (unslop, type-system-discipline, technical-writing, …)"
        // {default = true;};
      mattpocock.enable =
        lib.mkEnableOption "mattpocock/skills engineering-process library (spec → tickets → triage → implement → review)"
        // {default = true;};
      ms365.enable =
        lib.mkEnableOption "`m365claude` launcher (regular Claude + Microsoft 365 MCP). Kept out of the always-on servers because its 336 tool schemas cost 741K context tokens per session"
        // {default = true;};
      ms365.enabledTools = lib.mkOption {
        type = lib.types.str;
        default = "mail";
        example = "mail|excel|todo";
        description = "Regex handed to ms-365-mcp-server --enabled-tools, narrowing which of its 336 tools reach the context.";
      };
      dm-me.enable =
        lib.mkEnableOption "Discord DM-to-Alex skill + `dm-me` CLI (yelliv bot)"
        // {default = true;};
      mtg-commander.enable =
        lib.mkEnableOption "MTG Commander deckbuilding skill + `scryfall` bulk-data CLI"
        // {default = true;};
    };
    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        home.packages =
          [claudePoolPkg]
          ++ lib.optional cfg.ms365.enable m365ClaudePkg;

        # Sit out a rate limit instead of dying on it. Claude Code's default
        # 429 path gives up two ways: a retry-after longer than 60s is
        # rejected outright ("retry after too long"), and without one it
        # exhausts 10 exponential retries capped at 32s — measured at 11
        # attempts over 3m18s against a permanently-429ing upstream, which is
        # nothing next to a 5h window. This moves 429/overloaded onto the
        # persistent path: the attempt counter stops applying, backoff caps at
        # 5m instead of 32s, and anthropic-ratelimit-unified-reset is honoured
        # up to 6h. Verified against a fake upstream returning retry-after: 25
        # and recovering at 75s — four attempts spaced 25s apart, then the
        # turn completed.
        #
        # A session variable rather than an export in claudePoolPkg, because
        # the wrapper's fallback is the direct OAuth login, which hits the real
        # window just as hard, and `m365claude` skips the wrapper entirely.
        # t3code gets it from here too — it captures the environment through
        # `zsh -i -c` (see hm-features/zsh.nix) and hands process.env to the
        # CLI it spawns.
        #
        # Remove when upstream makes waiting the default for subscription
        # limits rather than something the runner opts into.
        home.sessionVariables.CLAUDE_CODE_RETRY_WATCHDOG = "1";

        home.activation.claude-settings = lib.hm.dag.entryAfter ["writeBoundary"] ''
          run ${lib.getExe mergeSettings}
        '';

        home.file = {
          ".claude/CLAUDE.md".text = globalClaudeMd;
          ".claude/skills/status".source = skills.status.path;
        };
      }
      # Vercel agent-browser: the CLI is a self-contained native binary (no
      # `agent-browser install` needed — it's pointed at a nix Chromium and
      # serves its own version-matched skill content). The upstream SKILL.md is
      # just a discovery stub telling the agent to run `agent-browser skills get
      # core`, so we symlink it into every config dir the three claude variants
      # use.
      (lib.mkIf cfg.agent-browser.enable (let
        skillStub = "${agentBrowserPkg}/share/agent-browser/skills/agent-browser/SKILL.md";
      in {
        home.packages = [agentBrowserPkg];
        home.file.".claude/skills/agent-browser/SKILL.md".source = skillStub;
      }))
      (lib.mkIf cfg.dm-me.enable {
        home.packages = [skills.dm-me-bin];
        home.file.".claude/skills/dm-me/SKILL.md".source = skills.dm-me.path;
      })
      (lib.mkIf cfg.mtg-commander.enable {
        home.packages = [skills.scryfall skills.gauntlet];
        home.file.".claude/skills/mtg-commander/SKILL.md".source =
          skills.mtg-commander.path;
      })
      # pstack + mattpocock: symlink each skill dir in. Skills-only installs — no
      # plugin registration, no SessionStart hook — so they stay as declarative
      # and disposable as the agent-browser stub above.
      (lib.mkIf cfg.pstack.enable {
        home.file = lib.mkMerge (map (skill: {
            ".claude/skills/${skill.name}".source = skill.path;
          })
          skills.pstack);
      })
      (lib.mkIf cfg.mattpocock.enable {
        home.file = lib.mkMerge (map (skill: {
            ".claude/skills/${skill.name}".source = skill.path;
          })
          skills.mattpocock);
      })
    ]);
  };
}
