{ ... }: {
  hmModules.features.claude-code = { config, lib, pkgs, ... }: {
    options.myHomeManager.claude-code.enable = lib.mkEnableOption "myHomeManager.claude-code";
    config = lib.mkIf config.myHomeManager.claude-code.enable {
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
