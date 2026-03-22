{ ... }: {
  hmModules.features.ghostty = { config, lib, ... }: {
    options.myHomeManager.ghostty.enable = lib.mkEnableOption "myHomeManager.ghostty";
    config = lib.mkIf config.myHomeManager.ghostty.enable {
      stylix.targets.ghostty.enable = true;
      programs.ghostty = {
        enable = true;
        settings = {
          window-decoration = false;
          window-padding-x = 0;
          window-padding-y = 0;
          confirm-close-surface = false;
          mouse-hide-while-typing = true;
        };
      };
    };
  };
}
