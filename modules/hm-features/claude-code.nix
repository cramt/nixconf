{inputs, ...}: {
  hmModules.features.claude-code = {
    config,
    lib,
    pkgs,
    ...
  }: let
    claudeCodePkg = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    agentBrowserPkg = pkgs.callPackage ../../packages/agent-browser {};

    # Every subdir under superpowers/skills is a self-contained skill (SKILL.md
    # + helper files). Enumerate them from the pinned source so new upstream
    # skills flow in on `npins update` without touching this file.
    superpowers = pkgs.npinsSources.superpowers;
    superpowersSkills =
      builtins.attrNames
      (lib.filterAttrs (_: type: type == "directory")
        (builtins.readDir "${superpowers}/skills"));
    # `linkedinclaude`: regular Claude with the stickerdaniel/linkedin-mcp-server
    # merged in for that session only (via --mcp-config, which adds to — not
    # replaces — the normal servers). Keeping it behind its own launcher means
    # the plain `claude` context isn't paying for LinkedIn's tool definitions
    # every session. Runs through Docker on purpose: the server bundles a
    # Patchright Chromium (a downloaded, dynamically-linked binary that won't
    # exec on NixOS) — the container carries its own working copy, so nothing
    # patchright-shaped ever has to run against the host's linker.
    linkedinDir = "${config.home.homeDirectory}/.linkedin-mcp";
    linkedinMcpConfig = pkgs.writeText "linkedin-mcp.json" (builtins.toJSON {
      mcpServers.linkedin = {
        command = "docker";
        # Upstream's README mounts `~/.linkedin-mcp`, but the MCP client hands
        # args to docker without a shell, so `~` would become a literal dir
        # named "~". Use the resolved absolute path.
        args = [
          "run"
          "--rm"
          "-i"
          "-v"
          "${linkedinDir}:/home/pwuser/.linkedin-mcp"
          "stickerdaniel/linkedin-mcp-server:latest"
        ];
      };
    });
    linkedinClaudePkg = pkgs.writeShellScriptBin "linkedinclaude" ''
      exec ${claudeCodePkg}/bin/claude --mcp-config ${linkedinMcpConfig} "$@"
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
      else
        # Drop any inherited routing so "fallback" really means direct — a
        # stale ANTHROPIC_BASE_URL in the shell (or a nested claude session)
        # would otherwise silently survive into the fallback path.
        unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN

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
  in {
    options.myHomeManager.claude-code = {
      enable = lib.mkEnableOption "myHomeManager.claude-code";
      agent-browser.enable =
        lib.mkEnableOption "Vercel agent-browser CLI + Claude Code skill"
        // {default = true;};
      superpowers.enable =
        lib.mkEnableOption "obra/superpowers skills library (TDD, debugging, planning)"
        // {default = true;};
      linkedin.enable =
        lib.mkEnableOption "`linkedinclaude` launcher (regular Claude + LinkedIn MCP via Docker). Needs a one-time host login writing cookies to ~/.linkedin-mcp — see the module comment"
        // {default = true;};
    };
    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        home.packages =
          lib.optional cfg.linkedin.enable linkedinClaudePkg
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
      # Superpowers: symlink each skill dir into every config dir the three
      # claude variants use. Skills-only install — no plugin registration, no
      # SessionStart hook — so it stays as declarative and disposable as the
      # agent-browser stub above.
      (lib.mkIf cfg.superpowers.enable {
        home.file = lib.mkMerge (map (skill: {
            ".claude/skills/${skill}".source = "${superpowers}/skills/${skill}";
          })
          superpowersSkills);
      })
    ]);
  };
}
