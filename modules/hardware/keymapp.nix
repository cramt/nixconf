# ZSA keyboard support — NixOS udev rules + HM keymapp package
{ ... }: {
  flake.nixosModules."features.keymapp" = { config, lib, ... }: {
    options.myNixOS.keymapp.enable = lib.mkEnableOption "myNixOS.keymapp";
    config = lib.mkIf config.myNixOS.keymapp.enable {
      hardware.keyboard.zsa.enable = true;
    };
  };

  hmModules.features.keymapp = { config, lib, pkgs, ... }: {
    options.myHomeManager.keymapp.enable = lib.mkEnableOption "myHomeManager.keymapp";
    config = lib.mkIf config.myHomeManager.keymapp.enable {
      home.packages = with pkgs; [
        keymapp
      ];
    };
  };
}
