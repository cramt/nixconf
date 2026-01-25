{
  pkgs,
  inputs,
  ...
}: {
  config = {
    stylix.targets.zen-browser.profileNames = ["default"];

    programs.zen-browser = {
      enable = true;
      policies = {
        DisableAppUpdate = true;
        DisableTelemetry = true;
      };
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = let
        browser = "zen-beta.desktop";
      in {
        "text/html" = browser;
        "text/xml" = browser;
        "application/xhtml+xml" = browser;
        "application/xml" = browser;
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
        "x-scheme-handler/about" = browser;
        "x-scheme-handler/unknown" = browser;
      };
    };
  };
}
