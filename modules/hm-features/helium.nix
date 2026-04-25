{ inputs, ... }: {
  hmModules.features.helium = { config, lib, pkgs, ... }: {
    options.myHomeManager.helium.enable = lib.mkEnableOption "myHomeManager.helium";
    config = lib.mkIf config.myHomeManager.helium.enable {
      home.packages = [
        inputs.helium-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };
  };
}
