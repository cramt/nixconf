{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.myHomeManager.firefox;
in {
  options.myHomeManager.firefox = {
    profiles = lib.mkOption {
      default = {
        cramt = {
          extensions = with pkgs.nur.repos.rycee.firefox-addons; [
            dashlane
            ublock-origin
            sponsorblock
            vimium
            refined-github
          ];

          search.force = true;

          settings = {
            "browser.disableResetPrompt" = true;
            "browser.download.panel.shown" = true;
            "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            "browser.shell.checkDefaultBrowser" = false;
            "browser.shell.defaultBrowserCheckCount" = 1;
            "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"nav-bar":["back-button","forward-button","stop-reload-button","home-button","urlbar-container","downloads-button","library-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["tabbrowser-tabs","new-tab-button","alltabs-button"],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["save-to-pocket-button","developer-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"dirtyAreaCache":["nav-bar","PersonalToolbar","toolbar-menubar","TabsToolbar","widget-overflow-fixed-list"],"currentVersion":18,"newElementCount":4}'';
            "dom.security.https_only_mode" = true;
            "identity.fxaccounts.enabled" = false;
            "privacy.trackingprotection.enabled" = true;
            "signon.rememberSignons" = false;
          };
        };
      };
      description = ''
        additional profiles
      '';
    };
  };
  config = {
    programs.firefox = {
      enable = true;
      profiles = cfg.profiles;
    };
    home.packages = builtins.attrValues (builtins.mapAttrs
      (name: value:
        pkgs.makeDesktopItem {
          name = "firefox ${name}";
          desktopName = "firefox ${name}";
          exec = "${pkgs.firefox}/bin/firefox -p ${name}";
        })
      cfg.profiles);
  };
}
