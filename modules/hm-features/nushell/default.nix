{ ... }: {
  hmModules.features.nushell = { config, lib, pkgs, ... }: {
    options.myHomeManager.nushell.enable = lib.mkEnableOption "myHomeManager.nushell";
    config = lib.mkIf config.myHomeManager.nushell.enable {
      programs.nushell = {
        enable = true;
        configFile.source = ./config.nu;
      };
    };
  };
}
