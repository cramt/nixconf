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
    options.myHomeManager.gpg-agent.enable = lib.mkEnableOption "myHomeManager.gpg-agent";
    config = lib.mkIf config.myHomeManager.gpg-agent.enable {
      services.gpg-agent = {
        enable = true;
        enableSshSupport = true;
        pinentry.package = pkgs.pinentry-tty;
        defaultCacheTtl = 86400;
        maxCacheTtl = 86400;
      };
      home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh";
      systemd.user.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh";
    };
  };
}
