{ inputs, ... }: {
  hmModules.features.playwright_driver = { config, lib, pkgs, ... }: {
    options.myHomeManager.playwright_driver.enable = lib.mkEnableOption "myHomeManager.playwright_driver";
    config = lib.mkIf config.myHomeManager.playwright_driver.enable {
      home.sessionVariables = {
        PLAYWRIGHT_BROWSERS_PATH = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.playwright-driver.browsers;
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
      };
    };
  };
}
