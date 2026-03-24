{ inputs, ... }: {
  hmModules.features.claude-code = { config, lib, pkgs, ... }:
  let
    claudeCodePkg = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    mkClaudeWithConfig = name: configDir: pkgs.writeShellScriptBin name ''
      export CLAUDE_CONFIG_DIR="${configDir}"
      exec ${claudeCodePkg}/bin/claude "$@"
    '';
  in {
    options.myHomeManager.claude-code.enable = lib.mkEnableOption "myHomeManager.claude-code";
    config = lib.mkIf config.myHomeManager.claude-code.enable {
      home.packages = [
        (mkClaudeWithConfig "claude-w" "$HOME/.claude-work")
        (mkClaudeWithConfig "claude-p" "$HOME/.claude-personal")
      ];
      home.file.".claude/CLAUDE.md".text = ''
        # Global Claude Code Instructions

        ## System Info

        This is a NixOS machine. Standard package managers (apt, yum, brew) are not available.

        ## Installing packages

        - Use `nix shell nixpkgs#<package>` to get a temporary shell with a package available
        - Use `nix-shell -p <package>` as an alternative
        - Examples:
          - `nix shell nixpkgs#python3` for Python
          - `nix shell nixpkgs#nodejs` for Node.js
          - `nix shell nixpkgs#gcc` for GCC
        - For running a single command: `nix run nixpkgs#<package> -- <args>`
        - Do NOT attempt to use apt, brew, pip install --user, or other non-Nix installation methods

        ## Git

        - Never add Co-Authored-By lines to commits
      '';
    };
  };
}
