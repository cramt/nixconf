{pkgs, ...}: {
  services.pcscd.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
    settings = {
      default-cache-ttl = 86400;
      max-cache-ttl = 86400;
    };
  };
}
