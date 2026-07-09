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
    # skills flow in on `nix flake update` without touching this file.
    superpowersSkills =
      builtins.attrNames
      (lib.filterAttrs (_: type: type == "directory")
        (builtins.readDir "${inputs.superpowers}/skills"));
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
          ++ lib.optional cfg.linkedin.enable linkedinClaudePkg;
        home.file = {
          ".claude/CLAUDE.md".text = globalClaudeMd;
          ".claude-work/CLAUDE.md".text = globalClaudeMd;
          ".claude-personal/CLAUDE.md".text = globalClaudeMd;
          ".claude/skills/status".source = ./claude-skills/status;
          ".claude-work/skills/status".source = ./claude-skills/status;
          ".claude-personal/skills/status".source = ./claude-skills/status;
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
        };
      }))
      # Superpowers: symlink each skill dir into every config dir the three
      # claude variants use. Skills-only install — no plugin registration, no
      # SessionStart hook — so it stays as declarative and disposable as the
      # agent-browser stub above.
      (lib.mkIf cfg.superpowers.enable {
        home.file = lib.mkMerge (lib.concatMap (base:
          map (skill: {
            "${base}/skills/${skill}".source = "${inputs.superpowers}/skills/${skill}";
          })
          superpowersSkills) [".claude" ".claude-work" ".claude-personal"]);
      })
    ]);
  };
}
