{ ... }: {
  flake.nixosModules."services.sshd" = {
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.services.sshd;
  in {
    options.myNixOS.services.sshd = {
      enable = lib.mkEnableOption "myNixOS.services.sshd";
    };
    config = lib.mkIf cfg.enable {
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
    };
  };
}
