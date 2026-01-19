{pkgs, ...}: {
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
    defaultCacheTtl = 86400;
    maxCacheTtl = 86400;
  };
}
