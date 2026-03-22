{ ... }: {
  hmModules.features.nix-index = { config, lib, pkgs, ... }: {
    options.myHomeManager.nix-index.enable = lib.mkEnableOption "myHomeManager.nix-index";
    config = lib.mkIf config.myHomeManager.nix-index.enable {
      programs.nix-index = { enable = true; enableZshIntegration = true; };
      programs.nix-index-database.comma.enable = true;
    };
  };
}
