{ ... }: {
  hmModules.features.fzf = { config, lib, ... }: {
    options.myHomeManager.fzf.enable = lib.mkEnableOption "myHomeManager.fzf";
    config = lib.mkIf config.myHomeManager.fzf.enable {
      programs.fzf.enable = true;
    };
  };
}
