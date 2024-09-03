{ input, inputs, outputs, config, pkgs, ... }:
{

  imports = [ outputs.homeManagerModules.default ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";


  myHomeManager = {
    bundles.general.enable = true;
    bundles.graphical.enable = true;
    bundles.work.enable = true;
    git.signingKey = "5A2AFD974351E6CA";
    blueman.enable = true;
    cockatrice.enable = true;
    firefox.profiles = {
      cramt = {
        extensions = with pkgs.nur.repos.rycee.firefox-addons;
          [
            dashlane
            ublock-origin
            sponsorblock
            vimium
            widegithub
          ];

        search.force = true;

        isDefault = false;

        id = 0;

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
      work = {
        extensions = with pkgs.nur.repos.rycee.firefox-addons;
          [
            ublock-origin
            sponsorblock
            vimium
            widegithub
          ];

        search.force = true;

        isDefault = true;

        id = 1;

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
    sway.monitors = {
      eDP-1 = {
        pos = "0 0";
        res = {
          width = 1920;
          height = 1200;
        };
        transform = 0;
        workspace = "1";
      };
      HDMI-A-1 = {
        pos = "-3440 -900";
        res = {
          width = 3440;
          height = 1440;
        };
        transform = 0;
        workspace = "2";
      };
      DP-6 = {
        pos = "-4880 -1500";
        res = {
          width = 2560;
          height = 1440;
        };
        transform = 270;
        workspace = "3";
      };
    };
  };

  home.stateVersion = "23.11";
}
