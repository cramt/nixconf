{ ... }: {
  hmModules.features.gtk = { config, lib, pkgs, ... }: {
    options.myHomeManager.gtk.enable = lib.mkEnableOption "myHomeManager.gtk";
    config = lib.mkIf config.myHomeManager.gtk.enable {
      gtk.enable = true;
      gtk.gtk4.theme = null;
    };
  };
}
