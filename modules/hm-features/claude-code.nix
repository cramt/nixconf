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

    # `claude` wrapper: point the normal Claude Code at the local model-splitter
    # (modules/services/claude-splitter.nix) instead of api.anthropic.com. No auth
    # token is set, so Claude Code keeps using its saved subscription OAuth — the
    # splitter forwards that verbatim to Anthropic for Claude models, and routes the
    # M365 slugs (e.g. `/model gpt-5.5-think-deeper`) to LiteLLM. hiPrio so it wins
    # over the raw claude-code binary the development bundle installs. Gated on the
    # splitter being enabled on this host.
    splitterReady = osConfig.myNixOS.services.claude-splitter.enable or false;
    splitterPort = osConfig.port-selector.ports.claude-splitter or null;
    claudeSplitPkg = lib.hiPrio (pkgs.writeShellScriptBin "claude" ''
      export ANTHROPIC_BASE_URL="http://127.0.0.1:${toString splitterPort}"
      # Surface the M365 gpt-5.5 tone in the `/model` picker. This env var adds a
      # single custom entry *additively* (the Anthropic models stay listed) —
      # there's no env for multiple, and the array form (availableModels) only
      # exists in settings layers, the global one of which replaces the whole list.
      export ANTHROPIC_CUSTOM_MODEL_OPTION="gpt-5.5-think-deeper"
      export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="GPT-5.5 Deep Research (M365)"
      exec ${claudeCodePkg}/bin/claude "$@"
    '');

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
          lib.optional cfg.linkedin.enable linkedinClaudePkg
          ++ lib.optional splitterReady claudeSplitPkg;
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
