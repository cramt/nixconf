{
  pkgs,
  inputs,
  ...
}: {
  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = inputs.nixpkgs-playwright.legacyPackages.${pkgs.system}.playwright-driver.browsers;
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };
}
