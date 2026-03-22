{ ... }: {
  hmModules.features.qt = { config, lib, pkgs, ... }: {
    options.myHomeManager.qt.enable = lib.mkEnableOption "myHomeManager.qt";
    config = lib.mkIf config.myHomeManager.qt.enable {
      qt = {
        enable = true;
        platformTheme = "adwaita";
        style = {
          name = "adwaita-dark";
          package = pkgs.adwaita-qt;
        };
      };
    };
  };
}
