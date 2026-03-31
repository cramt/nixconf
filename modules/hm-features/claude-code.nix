{ inputs, ... }: {
  hmModules.features.claude-code = { config, lib, pkgs, ... }:
  let
    claudeCodePkg = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    ecc = inputs.everything-claude-code;
    mkClaudeWithConfig = name: configDir: pkgs.writeShellScriptBin name ''
      export CLAUDE_CONFIG_DIR="${configDir}"
      exec ${claudeCodePkg}/bin/claude "$@"
    '';

    # Helper to collect all regular files from a directory into home.file entries
    symlinkDir = srcDir: destPrefix:
      lib.mapAttrs' (name: _:
        lib.nameValuePair "${destPrefix}/${name}" { source = "${srcDir}/${name}"; }
      ) (lib.filterAttrs (_: type: type == "regular") (builtins.readDir srcDir));

    # Recursively collect files from a directory tree
    symlinkDirRecursive = srcDir: destPrefix:
      let
        entries = builtins.readDir srcDir;
        files = lib.filterAttrs (_: type: type == "regular") entries;
        dirs = lib.filterAttrs (_: type: type == "directory") entries;
        fileLinks = lib.mapAttrs' (name: _:
          lib.nameValuePair "${destPrefix}/${name}" { source = "${srcDir}/${name}"; }
        ) files;
        dirLinks = lib.foldlAttrs (acc: name: _:
          acc // symlinkDirRecursive "${srcDir}/${name}" "${destPrefix}/${name}"
        ) {} dirs;
      in
        fileLinks // dirLinks;

    # ECC commands (top-level + .claude/commands with ecc- prefix)
    eccCommands =
      (symlinkDir "${ecc}/commands" ".claude/commands")
      // (lib.mapAttrs' (name: _:
        lib.nameValuePair ".claude/commands/ecc-${name}" { source = "${ecc}/.claude/commands/${name}"; }
      ) (lib.filterAttrs (_: type: type == "regular") (builtins.readDir "${ecc}/.claude/commands")));

    # ECC agents
    eccAgents = symlinkDir "${ecc}/agents" ".claude/agents";

    # ECC rules (recursive - common + per-language)
    eccRules = symlinkDirRecursive "${ecc}/rules" ".claude/rules";

    # ECC MCP config
    eccMcp = builtins.fromJSON (builtins.readFile "${ecc}/.mcp.json");

  in {
    options.myHomeManager.claude-code.enable = lib.mkEnableOption "myHomeManager.claude-code";
    config = lib.mkIf config.myHomeManager.claude-code.enable {
      home.packages = [
        (mkClaudeWithConfig "claude-w" "$HOME/.claude-work")
        (mkClaudeWithConfig "claude-p" "$HOME/.claude-personal")
      ];
      home.file = {
        ".claude/CLAUDE.md".text = ''
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

        # Global MCP servers from ECC
        ".claude/mcp.json".text = builtins.toJSON eccMcp;
      } // eccCommands // eccAgents // eccRules;
    };
  };
}
