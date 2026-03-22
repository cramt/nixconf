{ ... }: {
  hmModules.features.java = { config, lib, pkgs, ... }: {
    options.myHomeManager.java.enable = lib.mkEnableOption "myHomeManager.java";
    config = lib.mkIf config.myHomeManager.java.enable {
      home.packages = with pkgs; [ maven ];
      programs.java = {
        enable = true;
        package = pkgs.jdk;
      };
    };
  };
}
