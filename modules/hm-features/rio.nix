{ ... }: {
  hmModules.features.rio = { config, lib, pkgs, ... }: {
    options.myHomeManager.rio.enable = lib.mkEnableOption "myHomeManager.rio";
    config = lib.mkIf config.myHomeManager.rio.enable {
      programs.rio = {
        enable = true;
        settings = {
          confirm-before-quit = false;
          fonts = { size = lib.mkForce 16; };
          window.decorations = "Disabled";
          navigation.mode = "Plain";
          draw-bold-text-with-light-colors = true;
          hide-mouse-cursor-when-typing = true;
        };
      };
    };
  };
}
