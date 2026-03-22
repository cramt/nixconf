{ inputs, ... }: {
  hmModules.features.winapps = { config, lib, pkgs, ... }: {
    options.myHomeManager.winapps.enable = lib.mkEnableOption "myHomeManager.winapps";
    config = lib.mkIf config.myHomeManager.winapps.enable {
      xdg.configFile."winapps/winapps.conf".source = ./winapps.conf;
      home.packages = [
        inputs.winapps.packages."${pkgs.stdenv.hostPlatform.system}".winapps
        inputs.winapps.packages."${pkgs.stdenv.hostPlatform.system}".winapps-launcher
      ];
    };
  };
}
