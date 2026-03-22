{ ... }: {
  hmModules.features.distrobox = { config, lib, ... }: {
    options.myHomeManager.distrobox.enable = lib.mkEnableOption "myHomeManager.distrobox";
    config = lib.mkIf config.myHomeManager.distrobox.enable {
      programs.distrobox.enable = true;
    };
  };
}
