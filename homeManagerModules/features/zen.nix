{
  pkgs,
  lib,
  inputs,
  ...
}: let
  mkZenExtension = import ../../packages/mkZenExtension.nix {inherit pkgs;};

  extensions =
    (with pkgs.nur.repos.rycee.firefox-addons; [
      ublock-origin
      sponsorblock
      vimium
      refined-github
      onepassword-password-manager
      bitwarden
      multi-account-containers
    ])
    ++ [
      (mkZenExtension {
        name = "move-tab-to-new-window";
        shortcut = "Ctrl+Shift+M";
        description = "Move current tab to a new window";
        permissions = ["tabs"];
        js = ''
          browser.tabs.query({ active: true, currentWindow: true }).then((tabs) => {
            if (tabs[0]) {
              browser.windows.create({ tabId: tabs[0].id });
            }
          });
        '';
      })
    ];

  extensionSettings = builtins.listToAttrs (map (ext: {
    name = ext.addonId;
    value = {
      installation_mode = "force_installed";
    };
  }) extensions);
in {
  config = {
    stylix.targets.zen-browser.profileNames = ["default"];

    programs.zen-browser = {
      enable = true;
      policies = {
        DisableAppUpdate = true;
        DisableTelemetry = true;
        ExtensionSettings = extensionSettings;
      };
      profiles.default = {
        extensions.packages = extensions;

        settings = {
          "browser.disableResetPrompt" = true;
          "browser.download.panel.shown" = true;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          "browser.shell.checkDefaultBrowser" = false;
          "dom.security.https_only_mode" = true;
          "privacy.trackingprotection.enabled" = true;
          "signon.rememberSignons" = false;
          "privacy.userContext.enabled" = true;
          "privacy.userContext.ui.enabled" = true;
          "privacy.userContext.newTabContainerOnLeftClick.enabled" = true;
          "zen.view.compact.show-sidebar-and-toolbar-on-hover" = false;
        };

        mods = [
          "3ff55ba7-4690-4f74-96a8-9e4416685e4e" # Colored container tab
        ];

        containers = {
          personal = {
            id = 1;
            color = "red";
            icon = "fingerprint";
          };
          work = {
            id = 2;
            color = "blue";
            icon = "briefcase";
          };
        };
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
