{ ... }: {
  hmModules.features.wowup = { config, lib, pkgs, ... }: {
    options.myHomeManager.wowup.enable = lib.mkEnableOption "myHomeManager.wowup";
    config = lib.mkIf config.myHomeManager.wowup.enable {
      home.packages = with pkgs; [ wowup-cf ];
    };
  };
}
