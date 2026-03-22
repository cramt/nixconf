# UDisks2 automount
{ ... }: {
  flake.nixosModules."services.udisks" = { config, lib, ... }: {
    options.myNixOS.services.udisks.enable = lib.mkEnableOption "myNixOS.services.udisks";
    config = lib.mkIf config.myNixOS.services.udisks.enable {
      services.udisks2 = {
        enable = true;
        mountOnMedia = true;
      };
    };
  };
}
