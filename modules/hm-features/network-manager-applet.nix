{ ... }: {
  hmModules.features.network-manager-applet = { config, lib, ... }: {
    options.myHomeManager.network-manager-applet.enable = lib.mkEnableOption "myHomeManager.network-manager-applet";
    config = lib.mkIf config.myHomeManager.network-manager-applet.enable {
      services.network-manager-applet.enable = true;
    };
  };
}
