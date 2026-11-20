{...}: {
  flake.nixosModules."desktop.handoff-autologin" = {
    config,
    lib,
    ...
  }: let
    user = config.myNixOS.handoffAutologin.user;
    # claude-code.handoff's trigger (modules/hm-features/claude-code.nix).
    trigger = "${config.users.users.${user}.home}/.local/state/next-boot/claude-resume";
  in {
    options.myNixOS.handoffAutologin.user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Logs this user in on GDM without the greeter, for one boot, when a
        Claude Code session handed off before the reboot is waiting to be
        resumed (claude-code.handoff): the resumed session's terminal shows
        up with nobody at the keyboard. Every other boot keeps the greeter.
      '';
    };

    config = lib.mkIf (user != null) {
      systemd.services.handoff-autologin = {
        description = "GDM autologin for a Claude Code handoff, this boot only";
        unitConfig.ConditionPathExists = trigger;
        # Before the user's manager (linger), whose claude-resume removes
        # the trigger as it starts, and before GDM reads its config: both
        # wait for systemd-user-sessions.
        before = ["systemd-user-sessions.service" "display-manager.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        # /etc/gdm/custom.conf is a symlink the next activation puts back,
        # so pointing it elsewhere lasts this boot and touches no store file.
        script = ''
          {
            cat "$(readlink -f /etc/gdm/custom.conf)"
            printf '\n[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=%s\n' ${lib.escapeShellArg user}
          } > /run/gdm-handoff.conf
          ln -sfn /run/gdm-handoff.conf /etc/gdm/custom.conf
        '';
      };
    };
  };
}
