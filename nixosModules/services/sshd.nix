{
  config,
  lib,
  ...
}: {
  nix.sshServe = {
    enable = true;
    write = true;
    trusted = true;
    keys = lib.lists.flatten (lib.attrsets.mapAttrsToList (name: user: user.authorizedKeys) config.myNixOS.home-users);
  };
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
}
