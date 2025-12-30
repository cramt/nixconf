{
  pkgs,
  inputs,
  ...
}: {
  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.playwright-driver.browsers;
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };
}
