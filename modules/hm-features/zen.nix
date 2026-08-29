{ inputs, ... }: {
  hmModules.features.zen = { config, lib, pkgs, ... }: let
    mkZenExtension = import ../../packages/mkZenExtension.nix { inherit pkgs; };
  in {
    options.myHomeManager.zen.enable = lib.mkEnableOption "myHomeManager.zen";
    config = lib.mkIf config.myHomeManager.zen.enable {
      stylix.targets.zen-browser.profileNames = ["default"];
      programs.zen-browser = {
        enable = true;
        policies = { DisableAppUpdate = true; DisableTelemetry = true; };
        profiles.default = {
          extensions.packages =
            (with pkgs.nur.repos.rycee.firefox-addons; [
              ublock-origin sponsorblock vimium refined-github onepassword-password-manager bitwarden multi-account-containers
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
          settings = {
            # Extension versions are nix's to pick. Left on, Zen silently downloads a newer
            # xpi from AMO over HM's symlink; the next activation reverts it, and an addon
            # that bumped its IndexedDB schema in between (1Password does) can no longer open
            # its own DB. Drop these once extensions.packages installs read-only.
            "extensions.update.enabled" = false;
            "extensions.update.autoUpdateDefault" = false;
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
            # Let Zed's `zed://` sign-in callback hand off to the OS handler instead of
            # stalling as an unknown in-page navigation (Firefox blocks redirects to
            # unregistered external schemes). expose=false => treat as external protocol.
            "network.protocol-handler.expose.zed" = false;
            "network.protocol-handler.external.zed" = true;
            "network.protocol-handler.warn-external.zed" = false;
          };
          mods = [ "3ff55ba7-4690-4f74-96a8-9e4416685e4e" ];
          # The "Colored container tab" mod paints the selected tab from
          # `var(--identity-tab-color, var(--tab-group-color-gray-invert))`, but Firefox
          # calls that token --tab-group-gray-invert. Outside a container both names are
          # unset, so the color-mix() goes invalid-at-computed-value-time and the mod's
          # !important background-color computes to transparent — the active tab loses its
          # highlight entirely. Define the name the mod looks for, pointed at the theme
          # foreground so the 15%/20% mixes land near Zen's stock rgba(255,255,255,.15)
          # selection. Drop when the mod stops referencing the old token.
          userChrome = lib.mkAfter ''
            :root {
              --tab-group-color-gray-invert: ${config.lib.stylix.colors.withHashtag.base05};
            }
          '';
          containers = {
            personal = { id = 1; color = "red"; icon = "fingerprint"; };
            work = { id = 2; color = "blue"; icon = "briefcase"; };
          };
          # Zen rewrites containers.json at runtime (schema version bumps), which turns the
          # HM symlink back into a real file. Without force, activation tries to back it up
          # and dies permanently once a .hm-bak already exists.
          containersForce = true;
        };
      };
      xdg.mimeApps = {
        enable = true;
        defaultApplications = let browser = "zen-beta.desktop"; in {
          "text/html" = browser; "text/xml" = browser; "application/xhtml+xml" = browser;
          "application/xml" = browser; "x-scheme-handler/http" = browser;
          "x-scheme-handler/https" = browser; "x-scheme-handler/about" = browser;
          "x-scheme-handler/unknown" = browser;
        };
      };
    };
  };
}
