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

    cfg = config.myHomeManager.claude-code;

    extraMcpServers =
      (lib.optionalAttrs cfg.mcp.zammad.enable {
        zammad = {
          command = "${pkgs.uv}/bin/uvx";
          args = [
            "--from" "git+https://github.com/basher83/zammad-mcp.git"
            "mcp-zammad"
          ];
          env = {
            ZAMMAD_URL = cfg.mcp.zammad.url;
            ZAMMAD_HTTP_TOKEN_FILE = cfg.mcp.zammad.tokenFile;
          };
        };
      })
      // (lib.optionalAttrs cfg.mcp.ms365.enable {
        ms365 = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [ "-y" "@softeria/ms-365-mcp-server" ]
            ++ lib.optional cfg.mcp.ms365.orgMode "--org-mode"
            ++ lib.optional cfg.mcp.ms365.readOnly "--read-only";
          env = lib.optionalAttrs (cfg.mcp.ms365.clientId != null) {
            MS365_MCP_CLIENT_ID = cfg.mcp.ms365.clientId;
          };
        };
      });

    mergedMcp = eccMcp // {
      mcpServers = (eccMcp.mcpServers or {}) // extraMcpServers;
    };
    mcpJson = builtins.toJSON mergedMcp;

  in {
    options.myHomeManager.claude-code = {
      enable = lib.mkEnableOption "myHomeManager.claude-code";
      mcp.zammad = {
        enable = lib.mkEnableOption "Zammad MCP server (basher83/zammad-mcp)";
        url = lib.mkOption {
          type = lib.types.str;
          default = "https://support.re-zip.com/api/v1";
          description = "Zammad API base URL.";
        };
        tokenFile = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/opnix/secrets/zammadHttpToken";
          description = "Path to a file containing the Zammad HTTP API token.";
        };
      };
      mcp.ms365 = {
        enable = lib.mkEnableOption "Microsoft 365 MCP server (Softeria/ms-365-mcp-server) — Outlook/Teams/SharePoint/OneDrive via Graph";
        orgMode = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Pass --org-mode to enable work/school (Microsoft 365) features.";
        };
        readOnly = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Pass --read-only to disable all write operations (send/reply/draft/move/delete).";
        };
        clientId = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Azure AD application (client) ID to use instead of the server's
            built-in multi-tenant app. Leave null to use the built-in app
            (still requires tenant admin consent for the requested Graph scopes).
          '';
        };
      };
    };
    config = lib.mkIf cfg.enable {
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

      } // eccCommands // eccAgents // eccRules;

      # Claude Code reads user-scope MCP servers from <CLAUDE_CONFIG_DIR>/.claude.json
      # (or ~/.claude.json when CLAUDE_CONFIG_DIR is unset). It does NOT read any
      # ~/.claude/mcp.json. Register declaratively via `claude mcp add-json` for
      # each variant so plain `claude`, `claude-w`, and `claude-p` all see them.
      #
      # Runs as a user systemd unit (not a home.activation step) because each
      # `claude mcp` invocation is ~360ms of Node cold-start; 42 of them on the
      # boot critical path added ~15s to home-manager-cramt.service. As a user
      # unit started by default.target, it trails the login in the background.
      # home-manager auto-restarts the unit on switch when the script changes.
      systemd.user.services.claude-mcp-register = {
        Unit.Description = "Register Claude Code MCP servers";
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "register-claude-mcp" ''
            export PATH=${lib.makeBinPath [pkgs.jq pkgs.coreutils claudeCodePkg]}:$PATH
            SERVERS='${mcpJson}'

            register_dir() {
              if [ -n "$1" ]; then
                mkdir -p "$1"
                export CLAUDE_CONFIG_DIR="$1"
              else
                unset CLAUDE_CONFIG_DIR
              fi
              for name in $(jq -r '.mcpServers | keys[]' <<< "$SERVERS"); do
                server_json=$(jq -c --arg n "$name" '.mcpServers[$n]' <<< "$SERVERS")
                claude mcp remove -s user "$name" >/dev/null 2>&1 || true
                claude mcp add-json -s user "$name" "$server_json" >/dev/null
              done
            }

            register_dir ""
            register_dir "$HOME/.claude-work"
            register_dir "$HOME/.claude-personal"
          ''}";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
