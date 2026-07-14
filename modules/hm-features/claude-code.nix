{inputs, ...}: {
  hmModules.features.claude-code = {
    config,
    lib,
    pkgs,
    osConfig,
    ...
  }: let
    claudeCodePkg = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    agentBrowserPkg = pkgs.callPackage ../../packages/agent-browser {};

    # `claude-m365`: Claude Code pointed at the local M365 Copilot models instead
    # of Anthropic. Claude Code only speaks the Anthropic `/v1/messages` dialect,
    # so it goes through LiteLLM's Anthropic bridge (modules/services/litellm.nix),
    # which translates to the proxy's OpenAI endpoint. Only wired when both the
    # bridge and the proxy are enabled on this host; reads litellm's port from
    # osConfig so launcher and service can't drift (same trick as pi.nix).
    # Caveat: M365 backends can disengage on very large tool payloads — trim MCP
    # servers / tools if a session stops calling tools.
    m365ClaudeReady =
      (osConfig.myNixOS.services.litellm.enable or false)
      && (osConfig.myNixOS.services.m365-copilot-proxy.enable or false);
    litellmPort = osConfig.port-selector.ports.litellm or null;
    claudeM365Pkg = pkgs.writeShellScriptBin "claude-m365" ''
      export CLAUDE_CONFIG_DIR="$HOME/.claude-m365"
      export ANTHROPIC_BASE_URL="http://127.0.0.1:${toString litellmPort}"
      # LiteLLM has no master key configured, so any non-empty token passes.
      export ANTHROPIC_AUTH_TOKEN="dummy"
      # gpt-5.5-think-deeper (the "deep research" reasoning tone) is the default —
      # confirmed to hold tool calls in real sessions. Swap per-session with
      # `claude-m365 --model claude-sonnet-4.5` (or any exposed slug).
      export ANTHROPIC_MODEL="gpt-5.5-think-deeper"
      export ANTHROPIC_SMALL_FAST_MODEL="quick"
      export ANTHROPIC_DEFAULT_OPUS_MODEL="gpt-5.5-think-deeper"
      export ANTHROPIC_DEFAULT_SONNET_MODEL="gpt-5.5-think-deeper"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL="quick"
      exec ${claudeCodePkg}/bin/claude "$@"
    '';

    # Every subdir under superpowers/skills is a self-contained skill (SKILL.md
    # + helper files). Enumerate them from the pinned source so new upstream
    # skills flow in on `npins update` without touching this file.
    superpowers = pkgs.npinsSources.superpowers;
    superpowersSkills =
      builtins.attrNames
      (lib.filterAttrs (_: type: type == "directory")
        (builtins.readDir "${superpowers}/skills"));
    mkClaudeWithConfig = name: configDir:
      pkgs.writeShellScriptBin name ''
        export CLAUDE_CONFIG_DIR="${configDir}"
        exec ${claudeCodePkg}/bin/claude "$@"
      '';

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
          [
            (mkClaudeWithConfig "claude-w" "$HOME/.claude-work")
            (mkClaudeWithConfig "claude-p" "$HOME/.claude-personal")
          ]
          ++ lib.optional cfg.linkedin.enable linkedinClaudePkg
          ++ lib.optional m365ClaudeReady claudeM365Pkg;
        home.file = {
          ".claude/CLAUDE.md".text = globalClaudeMd;
          ".claude-work/CLAUDE.md".text = globalClaudeMd;
          ".claude-personal/CLAUDE.md".text = globalClaudeMd;
          ".claude-m365/CLAUDE.md".text = globalClaudeMd;
          ".claude/skills/status".source = ./claude-skills/status;
          ".claude-work/skills/status".source = ./claude-skills/status;
          ".claude-personal/skills/status".source = ./claude-skills/status;
          ".claude-m365/skills/status".source = ./claude-skills/status;
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
        home.file = {
          ".claude/skills/agent-browser/SKILL.md".source = skillStub;
          ".claude-work/skills/agent-browser/SKILL.md".source = skillStub;
          ".claude-personal/skills/agent-browser/SKILL.md".source = skillStub;
          ".claude-m365/skills/agent-browser/SKILL.md".source = skillStub;
        };
      }))
      # Superpowers: symlink each skill dir into every config dir the three
      # claude variants use. Skills-only install — no plugin registration, no
      # SessionStart hook — so it stays as declarative and disposable as the
      # agent-browser stub above.
      (lib.mkIf cfg.superpowers.enable {
        home.file = lib.mkMerge (lib.concatMap (base:
          map (skill: {
            "${base}/skills/${skill}".source = "${superpowers}/skills/${skill}";
          })
          superpowersSkills) [".claude" ".claude-work" ".claude-personal" ".claude-m365"]);
      })
    ]);
  };
}
