{ ... }: {
  hmModules.features.mako = { config, lib, pkgs, ... }: let
    colors = config.colorScheme.colors;
  in {
    options.myHomeManager.mako.enable = lib.mkEnableOption "myHomeManager.mako";
    config = lib.mkIf config.myHomeManager.mako.enable {
      services.mako = {
        enable = true;
        settings = {
          anchor = "bottom-right";
          margin = "0,20,20";
          padding = "10";
          groupBy = "summary";
          format = "<b>%s</b>\\n%b";
        };
      };
    };
  };
}
