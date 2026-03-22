{ ... }: {
  hmModules.features.lazygit = { config, lib, ... }: {
    options.myHomeManager.lazygit.enable = lib.mkEnableOption "myHomeManager.lazygit";
    config = lib.mkIf config.myHomeManager.lazygit.enable {
      programs.lazygit = {
        enable = true;
        settings = { gui = { authorColors = { "Alexandra Østermark" = "#b00b69"; }; }; };
      };
    };
  };
}
