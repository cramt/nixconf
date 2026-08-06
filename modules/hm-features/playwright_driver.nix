{ inputs, ... }: {
  hmModules.features.playwright_driver = { config, lib, pkgs, ... }: {
    options.myHomeManager.playwright_driver.enable = lib.mkEnableOption "myHomeManager.playwright_driver";
    config = lib.mkIf config.myHomeManager.playwright_driver.enable {
      home.sessionVariables = {
        # Held on stable (1.59.1, vs 1.61.1 on unstable) on purpose: the browser
        # bundle has to match the `playwright` npm client a project resolves, and
        # bumping this is what breaks "Executable doesn't exist" at test time.
        # Move it when the projects that use it move.
        PLAYWRIGHT_BROWSERS_PATH = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.playwright-driver.browsers;
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
      };
    };
  };
}
