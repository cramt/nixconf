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

    cfg = config.myHomeManager.claude-code;

    globalClaudeMd = ''
      # Global Claude Code Instructions

      ## System Info

      This is a NixOS machine. Standard package managers (apt, yum, brew) are not available.

      ## Installing packages

      - Use `nix shell nixpkgs#<package>` to get a temporary shell with a package available
      - Examples:
        - `nix shell nixpkgs#python3` for Python
        - `nix shell nixpkgs#nodejs` for Node.js
        - `nix shell nixpkgs#gcc` for GCC
      - For running a single command: `nix run nixpkgs#<package> -- <args>`
      - Do NOT attempt to use apt, brew, pip install --user, or other non-Nix installation methods

      ## Git and GitHub

      - Never add Co-Authored-By lines to commits
      - The gh cli is available and authed, feel free to use
      - When making a pr dont add "Created by Claude Code"

      ## Root
      - If you ever need me to run a command (like fx its a sudo .. command) be sure to throw it in my clipboard with wl-copy
      - If you also want the output from a command above have the command end in `| wl-copy` so i can easily copy it back

      ## Coding Style
      - If a thing can reasonably be declaratively done it should (this includes your own config), This is why we love nix
      - `Make Invalid States Unrepresentable` is the most important single statement in all of software engineering. This is why we love languages with proper algebraic type systems like typescript and rust

      ## Tone
      - Never be overly formal. I'm a down to earth engineer, you can be too

      ## Comments
      - Don't add comments that just restate what the code already says
      - Comment the *why*, not the *what* — context, tradeoffs, and non-obvious reasoning are worth writing down
      - Prefer clear naming and structure over explanatory comments
    '';
  in {
    options.myHomeManager.claude-code = {
      enable = lib.mkEnableOption "myHomeManager.claude-code";
      agent-browser.enable =
        lib.mkEnableOption "Vercel agent-browser CLI + Claude Code skill"
        // {default = true;};
      superpowers.enable =
        lib.mkEnableOption "obra/superpowers skills library (TDD, debugging, planning)"
        // {default = true;};
    };
    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        home.packages = [
          (mkClaudeWithConfig "claude-w" "$HOME/.claude-work")
          (mkClaudeWithConfig "claude-p" "$HOME/.claude-personal")
        ];
        home.file = {
          ".claude/CLAUDE.md".text = globalClaudeMd;
          ".claude-work/CLAUDE.md".text = globalClaudeMd;
          ".claude-personal/CLAUDE.md".text = globalClaudeMd;
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
