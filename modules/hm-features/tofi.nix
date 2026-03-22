{ ... }: {
  hmModules.features.tofi = { config, lib, pkgs, ... }: {
    options.myHomeManager.tofi.enable = lib.mkEnableOption "myHomeManager.tofi";
    config = lib.mkIf config.myHomeManager.tofi.enable {
      programs.tofi.enable = true;
    };
  };
}
