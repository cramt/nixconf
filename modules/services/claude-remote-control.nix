# `claude remote-control` as an always-on server, so claude.ai/code and the
# phone app always have this host to hand sessions to.
#
# Same shape as t3code.nix: a `systemd --user` unit of a real login user, so
# spawned sessions get that user's ~/.claude (skills, CLAUDE.md, transcripts)
# and home-manager PATH. Remote Control only works on a claude.ai OAuth login,
# never an API key or the cli-proxy-api pool, which is why this calls the raw
# claude-code binary rather than the pool wrapper. The login itself is
# interactive (`claude auth login` as the user) and lives in ~/.claude.json.
{inputs, ...}: {
  flake.nixosModules."services.claude-remote-control" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.claude-remote-control;
    claudeCodePkg = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
  in {
    options.myNixOS.services.claude-remote-control = {
      enable = lib.mkEnableOption "myNixOS.services.claude-remote-control";
      user = lib.mkOption {
        type = lib.types.str;
        default = "cramt";
        description = "Login user whose `systemd --user` manager runs the server. Must be one of this host's home-users.";
      };
      workingDirectory = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user}";
        defaultText = lib.literalExpression ''"/home/''${user}"'';
        description = ''
          Where new sessions start. Claude Code refuses to serve a directory
          whose workspace-trust dialog was never accepted, so run `claude` there
          once by hand first.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      # Headless: bring the user manager up at boot without a login.
      users.users.${cfg.user}.linger = true;

      home-manager.users.${cfg.user} = {...}: {
        systemd.user.services.claude-remote-control = {
          Unit.Description = "Claude Code Remote Control server";
          Install.WantedBy = ["default.target"];
          Service = {
            ExecStart = "${claudeCodePkg}/bin/claude remote-control";
            WorkingDirectory = cfg.workingDirectory;
            Environment = [
              # systemd --user doesn't put the per-user profile on PATH, and
              # sessions need git/ssh and friends.
              "PATH=/home/${cfg.user}/.nix-profile/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin"
              # home.sessionVariables from hm-features/claude-code.nix don't
              # reach systemd units; see there for why this matters.
              "CLAUDE_CODE_RETRY_WATCHDOG=1"
            ];
            # stdout is the status TUI repainting ~8 lines/s even with no TTY,
            # which would be ~700k journal lines a day. Errors (e.g. a lapsed
            # login) go to stderr and still land in the journal.
            StandardOutput = "null";
            Restart = "always";
            RestartSec = "10";
            # Sessions are children sharing this cgroup; one OOMing tool call
            # shouldn't take the server and every other session down.
            OOMPolicy = "continue";
          };
        };
      };
    };
  };
}
