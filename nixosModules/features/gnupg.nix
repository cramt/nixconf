{pkgs, ...}: {
  # pcscd for smartcard support (e.g., YubiKey)
  services.pcscd.enable = true;

  # NixOS-level gnupg agent - SSH support is handled by Home Manager's
  # services.gpg-agent for proper systemd user session integration
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
    pinentryPackage = pkgs.pinentry-curses;
  };
}
