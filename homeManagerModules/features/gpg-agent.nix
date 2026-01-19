{pkgs, config, ...}: {
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
    defaultCacheTtl = 86400;
    maxCacheTtl = 86400;
  };

  # Override SSH_AUTH_SOCK to use gpg-agent instead of gnome-keyring
  # (PAM sets it to keyring path via pam_gnome_keyring during login)
  # Setting in both places to ensure it's available everywhere:
  # - home.sessionVariables: for shells that source hm-session-vars.sh
  # - systemd.user.sessionVariables: for systemd user services
  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh";
  systemd.user.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh";
}
