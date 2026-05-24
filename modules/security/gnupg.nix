# GnuPG — NixOS smartcard/agent + HM gpg-agent with SSH support
{ ... }: {
  flake.nixosModules."features.gnupg" = { config, lib, pkgs, ... }: {
    options.myNixOS.gnupg.enable = lib.mkEnableOption "myNixOS.gnupg";
    config = lib.mkIf config.myNixOS.gnupg.enable {
      services.pcscd.enable = true;
      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = false;
        pinentryPackage = pkgs.pinentry-curses;
      };
    };
  };

  hmModules.features.gpg-agent = { config, lib, pkgs, ... }: {
    options.myHomeManager.gpg-agent = {
      enable = lib.mkEnableOption "myHomeManager.gpg-agent";
      enableSshSupport = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether gpg-agent should also serve as the SSH agent (sets
          SSH_AUTH_SOCK to the gpg-agent socket). Disable on hosts that
          want to use a forwarded SSH agent or an external one (e.g. 1Password).
        '';
      };
    };
    config = lib.mkIf config.myHomeManager.gpg-agent.enable (lib.mkMerge [
      {
        services.gpg-agent = {
          enable = true;
          enableSshSupport = config.myHomeManager.gpg-agent.enableSshSupport;
          pinentry.package = pkgs.pinentry-tty;
          defaultCacheTtl = 86400;
          maxCacheTtl = 86400;
        };
      }
      (lib.mkIf config.myHomeManager.gpg-agent.enableSshSupport {
        home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh";
        systemd.user.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh";
      })
    ]);
  };
}
