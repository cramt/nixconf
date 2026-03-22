{ ... }: {
  hmModules.features.noctalia = { config, lib, pkgs, ... }: {
    options.myHomeManager.noctalia.enable = lib.mkEnableOption "myHomeManager.noctalia";
    config = lib.mkIf config.myHomeManager.noctalia.enable {
      programs.noctalia-shell = {
        enable = true;
      };
    };
  };
}
