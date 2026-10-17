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

    # `reaclaude`: regular (pooled) Claude plus REA's reverse-engineering MCP
    # server and skill, loaded as a session-only plugin (or into plain `claude`
    # with rea.alwaysOn, as on luna). Kept out of the
    # always-on servers for the same reason as m365: 207 tools cost 75K
    # context tokens over a 32K floor even with the compact input and no-output
    # schema profiles (3 MB of JSON → 215 KB); full schemas would be ~750K.
    # Measured with the m365 benchmark below. The skill rides along in the
    # plugin because it's only useful with the server attached.
    reaPlugin = pkgs.linkFarm "rea-claude-plugin" {
      ".claude-plugin/plugin.json" = pkgs.writeText "plugin.json" (builtins.toJSON {
        name = "rea";
        inherit (pkgs.rea-agents) version;
        description = "REA reverse-engineering MCP server and skill";
      });
      ".mcp.json" = pkgs.writeText "rea-mcp.json" (builtins.toJSON {
        mcpServers.rea = {
          command = lib.getExe pkgs.rea-agents;
          args = ["mcp"];
          env = {
            REA_MCP_INPUT_SCHEMA_PROFILE = "compact";
            REA_MCP_OUTPUT_SCHEMA_PROFILE = "off";
            GHIDRA_INSTALL_DIR = "${pkgs.ghidra}/lib/ghidra";
          };
        };
      });
      "skills/reverse-engineer-anything" = pkgs.rea-agents.skill;
    };
    reaClaudePkg = pkgs.writeShellScriptBin "reaclaude" ''
      exec ${claudePoolPkg}/bin/claude --plugin-dir ${reaPlugin} "$@"
    '';
    reaAlwaysOn = cfg.rea.enable && cfg.rea.alwaysOn;

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
        # An auth token isn't a claude.ai login, so Claude Code drops to the
        # API-key default of a 5m prompt cache; a subscriber gets 1h on the
        # main thread. This restores that, and only that: subagents read
        # CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL and stay at 5m, as natively.
        # The proxy passes a native client's cache_control through untouched.
        export CLAUDE_CODE_PROMPT_CACHE_TTL=1h
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

      exec ${claudeCodePkg}/bin/claude ${lib.optionalString reaAlwaysOn "--plugin-dir ${reaPlugin}"} "$@"
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
      rea.enable =
        lib.mkEnableOption "`reaclaude` launcher (regular Claude + REA reverse-engineering MCP, skill and Ghidra). Kept out of the always-on servers because its 207 tool schemas cost 75K context tokens per session"
        // {default = true;};
      rea.alwaysOn = lib.mkEnableOption "loading the REA plugin into plain `claude` on every session instead of behind `reaclaude`, paying its 75K context tokens each time";
      dm-me.enable =
        lib.mkEnableOption "Discord DM-to-Alex skill + `dm-me` CLI (yelliv bot)"
        // {default = true;};
      mtg.enable =
        lib.mkEnableOption "MTG skills (general + Commander) + `scryfall` bulk-data CLI and `gauntlet`"
        // {default = true;};
      agents = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.str;
              description = "When the main agent should delegate here; Claude Code routes on it.";
            };
            model = lib.mkOption {
              type = lib.types.str;
              description = "Anything `--model` takes, including a pool model id like `m365/gpt-5.5[1m]`.";
            };
            prompt = lib.mkOption {
              type = lib.types.str;
              description = "The subagent's system prompt.";
            };
          };
        });
        default = {};
        description = "Subagents, rendered to ~/.claude/agents/<name>.md.";
      };
    };
    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        # Not for me, for the agent: it reaches for `python3 - <<'EOF'` to edit
        # files no matter what CLAUDE.md says. Without it, 147 of those calls
        # failed in a month of transcripts (2026-09-14..10-14, half of all
        # sessions), and a few chained ones failed silently and shipped the
        # unedited file, conflict markers included.
        home.packages =
          [claudePoolPkg pkgs.python3]
          ++ lib.optional cfg.ms365.enable m365ClaudePkg
          ++ lib.optional cfg.rea.enable pkgs.rea-agents
          ++ lib.optional (cfg.rea.enable && !reaAlwaysOn) reaClaudePkg;

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
          ".claude/skills/write-like-alex".source = skills.write-like-alex.path;
          ".claude/skills/gm".source = skills.gm.path;
        }
        // lib.mapAttrs' (name: agent:
          lib.nameValuePair ".claude/agents/${name}.md" {
            text = ''
              ---
              name: ${builtins.toJSON name}
              description: ${builtins.toJSON agent.description}
              model: ${builtins.toJSON agent.model}
              ---

              ${agent.prompt}
            '';
          })
        cfg.agents;

        # M365 Copilot through the pool (cli-proxy-api on luna routes m365/ to
        # the M365 proxy). gpt-5.5-think-deeper because it's the proxy's best
        # measured tool-caller (26/30 on its bench); a caller can still pass
        # another m365/ model per Agent call.
        myHomeManager.claude-code.agents.m365 = {
          description = "General-purpose worker running on Microsoft 365 Copilot (GPT) instead of Claude. Use when asked to delegate to M365/Copilot/GPT, or to get a second opinion from a non-Claude model.";
          model = "m365/gpt-5.5-think-deeper[1m]";
          prompt = ''
            You are a general-purpose coding subagent. Do the task you were
            given with the tools you have, then report back concisely: what you
            did, what you found, and anything left undone. Run commands rather
            than guessing at their output.
          '';
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
      (lib.mkIf cfg.mtg.enable {
        home.packages = [skills.scryfall skills.gauntlet skills.mtg-lore];
        home.file = {
          ".claude/skills/mtg/SKILL.md".source = skills.mtg.path;
          ".claude/skills/mtg-commander".source = skills.mtg-commander.path;
        };
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
