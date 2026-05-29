# Always-on `claude remote-control` session so a new instance is always
# available to attach to from the Claude mobile app / claude.ai/code without
# needing to leave a terminal open by hand.
{ inputs, ... }: {
  flake.nixosModules."services.claude-remote-control" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.claude-remote-control;
    claudeCodePkg = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

    # Claude refuses to start in an untrusted workspace, and the trust prompt
    # can't be shown headless — so it fails closed. There is no
    # `--trust-workspace` flag (only `--dangerously-skip-permissions`, which
    # also disables *all* permission checks for every spawned session — too
    # broad). Instead we pre-seed the one flag Claude checks:
    # `.projects["<dir>"].hasTrustDialogAccepted` in ~/.claude.json, merging it
    # in without clobbering the rest of that mutable runtime file.
    trustWorkspaceScript = pkgs.writeShellScript "claude-trust-workspace" ''
      set -euo pipefail
      config="$HOME/.claude.json"
      dir=${lib.escapeShellArg cfg.workingDirectory}
      tmp="$(${pkgs.coreutils}/bin/mktemp "$HOME/.claude.json.XXXXXX")"
      trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
      if [ -f "$config" ]; then
        ${pkgs.jq}/bin/jq --arg d "$dir" \
          '.projects[$d].hasTrustDialogAccepted = true
           | .projects[$d].hasCompletedProjectOnboarding = true' \
          "$config" > "$tmp"
      else
        ${pkgs.jq}/bin/jq -n --arg d "$dir" \
          '{projects: {($d): {hasTrustDialogAccepted: true, hasCompletedProjectOnboarding: true}}}' \
          > "$tmp"
      fi
      ${pkgs.coreutils}/bin/mv "$tmp" "$config"
      trap - EXIT
    '';
  in {
    options.myNixOS.services.claude-remote-control = {
      enable = lib.mkEnableOption "myNixOS.services.claude-remote-control";
      user = lib.mkOption {
        type = lib.types.str;
        default = "cramt";
        description = ''
          User to run the remote-control session as. This user must already be
          authenticated to claude.ai — the credentials in their `~/.claude` are
          what the session uses. The service can't log in for you.
        '';
      };
      workingDirectory = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user}";
        defaultText = lib.literalExpression ''"/home/''${cfg.user}"'';
        description = "Directory the session starts in. Defaults to the user's home.";
      };
      trustWorkspace = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Pre-mark `workingDirectory` as a trusted workspace in
          `~/.claude.json` before launch, so the headless session doesn't fail
          on the workspace-trust dialog (which can't be shown without a TTY).
          Only this directory is trusted; normal permission prompts still apply
          to spawned sessions.
        '';
      };
    };
    config = lib.mkIf cfg.enable {
      systemd.services.claude-remote-control = {
        description = "Always-on Claude Code remote-control session";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];
        # git/coreutils on PATH so the attached session behaves like a normal
        # shell; nix itself is already on the system PATH.
        path = [pkgs.git pkgs.coreutils claudeCodePkg];
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          # systemd derives $HOME/$USER from the account, so `claude` finds
          # ~/.claude credentials.
          WorkingDirectory = cfg.workingDirectory;
          ExecStartPre = lib.mkIf cfg.trustWorkspace ["${trustWorkspaceScript}"];
          ExecStart = "${claudeCodePkg}/bin/claude remote-control";
          # Respawn on crash or the ~10-min network-outage timeout so the
          # session is always there for the phone to attach to.
          Restart = "always";
          RestartSec = 5;
        };
      };
    };
  };
}
