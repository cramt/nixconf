{inputs, ...}: {
  hmModules.features.claude-code = {
    config,
    lib,
    pkgs,
    ...
  }: let
    claudeCodePkg = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    agentBrowserPkg = pkgs.callPackage ../../packages/agent-browser {};

    # Vendored rather than pinned: upstream pstack is one tree rooted at
    # `poteto-mode`, and only these ten stand alone. Each also needs its
    # `disable-model-invocation` flag stripped to fire without that dispatcher,
    # so there's nothing for a pin to track cleanly. See ./claude-skills/pstack/README.md.
    pstackDir = ./claude-skills/pstack;
    pstackSkills =
      builtins.attrNames
      (lib.filterAttrs (_: type: type == "directory")
        (builtins.readDir pstackDir));

    # mattpocock/skills nests a category level (skills/<category>/<name>), so
    # flatten two deep. Enumerating rather than listing means new upstream skills
    # arrive on `just update`; the exclusion is the only thing to maintain.
    # setup-matt-pocock-skills rewrites a repo's issue-tracker and label
    # vocabulary to match upstream's conventions, which ours don't follow.
    mattpocockExclude = ["setup-matt-pocock-skills"];
    mattpocockRoot = "${inputs.mattpocock-skills}/skills";
    dirsIn = path:
      builtins.attrNames
      (lib.filterAttrs (_: type: type == "directory") (builtins.readDir path));
    mattpocockSkills =
      lib.filter (s: !(builtins.elem s.name mattpocockExclude))
      (lib.concatMap
        (category:
          map (name: {
            inherit name;
            path = "${mattpocockRoot}/${category}/${name}";
          })
          (dirsIn "${mattpocockRoot}/${category}"))
        (dirsIn mattpocockRoot));

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

    # `claude` wrapper: point Claude Code at the local cli-proxy-api (see
    # modules/hm-features/cli-proxy-api.nix) so requests are spread over the
    # pooled Claude accounts instead of the single OAuth login in ~/.claude.
    # The proxy authenticates upstream with its own stored tokens, so what
    # Claude Code sends is the proxy's local api key — ANTHROPIC_API_KEY is
    # cleared so it can't fall back to a real Anthropic key. hiPrio to win over
    # the raw claude-code binary the development bundle installs.
    # Falls back to Claude Code's own OAuth whenever the pool can't serve: an
    # empty pool is the normal state right after a deploy (accounts are added
    # by an interactive `agent-accounts add`, which Nix can't do), and silently
    # routing at that point would break `claude` entirely rather than degrade.
    proxyCfg = config.myHomeManager.cli-proxy-api;
    claudePoolPkg = lib.hiPrio (pkgs.writeShellScriptBin "claude" ''
      authdir="$HOME/.cli-proxy-api"
      keyfile="$authdir/local-api-key"
      accounts=$(find "$authdir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)

      if [ -s "$keyfile" ] && [ "$accounts" -gt 0 ] &&
         timeout 1 bash -c '</dev/tcp/127.0.0.1/${toString proxyCfg.port}' 2>/dev/null; then
        export ANTHROPIC_BASE_URL="http://127.0.0.1:${toString proxyCfg.port}"
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

        if [ "$accounts" -eq 0 ]; then
          echo "claude: cli-proxy-api has no accounts yet — using the direct OAuth login." >&2
          echo "        add one with: agent-accounts add" >&2
        else
          echo "claude: cli-proxy-api unreachable on 127.0.0.1:${toString proxyCfg.port} — using the direct OAuth login." >&2
          echo "        systemctl --user status cli-proxy-api" >&2
        fi
      fi

      exec ${claudeCodePkg}/bin/claude "$@"
    '');

    # Shared with pi (written to ~/.pi/agent/AGENTS.md by modules/hm-features/pi.nix)
    # — single source of truth so the two agents' global instructions can't drift.
    globalClaudeMd = builtins.readFile ./global-agent-instructions.md;

    # The mtg-commander skill leans on this helper for every card lookup, so it
    # gets a real derivation with its deps closed over rather than a bare script
    # in the skill dir: an agent that can't find `jq` would silently fall back to
    # guessing card data from memory, which is the one thing the skill forbids.
    scryfallPkg = pkgs.writeShellApplication {
      name = "scryfall";
      runtimeInputs = with pkgs; [curl jq gzip util-linux];
      text = builtins.readFile ./claude-skills/mtg-commander/scryfall.sh;
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
      mtg-commander.enable =
        lib.mkEnableOption "MTG Commander deckbuilding skill + `scryfall` bulk-data CLI"
        // {default = true;};
    };
    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        home.packages =
          lib.optional cfg.ms365.enable m365ClaudePkg
          ++ lib.optional proxyCfg.enable claudePoolPkg;
        home.file = {
          ".claude/CLAUDE.md".text = globalClaudeMd;
          ".claude/skills/status".source = ./claude-skills/status;
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
      (lib.mkIf cfg.mtg-commander.enable {
        home.packages = [scryfallPkg];
        home.file.".claude/skills/mtg-commander/SKILL.md".source =
          ./claude-skills/mtg-commander/SKILL.md;
      })
      # pstack + mattpocock: symlink each skill dir in. Skills-only installs — no
      # plugin registration, no SessionStart hook — so they stay as declarative
      # and disposable as the agent-browser stub above.
      (lib.mkIf cfg.pstack.enable {
        home.file = lib.mkMerge (map (skill: {
            ".claude/skills/${skill}".source = "${pstackDir}/${skill}";
          })
          pstackSkills);
      })
      (lib.mkIf cfg.mattpocock.enable {
        home.file = lib.mkMerge (map (skill: {
            ".claude/skills/${skill.name}".source = skill.path;
          })
          mattpocockSkills);
      })
    ]);
  };
}
