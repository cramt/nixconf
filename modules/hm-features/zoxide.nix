{ ... }: {
  hmModules.features.zoxide = { config, lib, ... }: {
    options.myHomeManager.zoxide.enable = lib.mkEnableOption "myHomeManager.zoxide";
    config = lib.mkIf config.myHomeManager.zoxide.enable {
      programs.zoxide = { enable = true; enableZshIntegration = true; };
    };
  };
}
