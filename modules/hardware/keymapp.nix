# ZSA keyboard support — udev rules only.
#
# The keymapp GUI used to ship alongside these rules and was never once
# launched; Oryx (the web flasher) only needs the rules, so the package went
# and `hardware.keyboard.zsa` stayed.
{ ... }: {
  flake.nixosModules."features.keymapp" = { config, lib, ... }: {
    options.myNixOS.keymapp.enable = lib.mkEnableOption "myNixOS.keymapp";
    config = lib.mkIf config.myNixOS.keymapp.enable {
      hardware.keyboard.zsa.enable = true;
    };
  };
}
