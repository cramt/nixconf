{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.myHomeManager.waydroid;

  # Generate a desktop entry for a Waydroid app
  makeDesktopEntry = app: {
    name = "waydroid-${app.id}";
    value = {
      name = app.name;
      comment =
        if app.comment != null
        then app.comment
        else "Android app running in Waydroid";
      exec = "${pkgs.waydroid}/bin/waydroid app launch ${app.id}";
      icon =
        if app.icon != null
        then app.icon
        else "waydroid";
      terminal = false;
      type = "Application";
      categories = app.categories;
      settings = {
        StartupWMClass = "Waydroid";
      };
    };
  };

  # Convert app definitions to desktop entries
  desktopEntries = builtins.listToAttrs (map makeDesktopEntry cfg.apps);
in {
  options.myHomeManager.waydroid.apps = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        id = lib.mkOption {
          type = lib.types.str;
          description = "Android package ID (e.g., com.microsoft.teams)";
          example = "com.microsoft.teams";
        };

        name = lib.mkOption {
          type = lib.types.str;
          description = "Display name for the desktop entry";
          example = "Microsoft Teams";
        };

        comment = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Description/comment for the desktop entry";
          example = "Chat and collaboration app";
        };

        icon = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Icon name or path. Defaults to 'waydroid' if not specified.";
          example = "teams";
        };

        categories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["Application"];
          description = "Desktop entry categories";
          example = ["Network" "Chat"];
        };
      };
    });
    default = [];
    description = "List of Waydroid apps to create desktop entries for.";
    example = [
      {
        id = "com.microsoft.teams";
        name = "Microsoft Teams";
        comment = "Chat and collaboration";
        categories = ["Network" "Chat"];
      }
      {
        id = "org.mozilla.fennec_fdroid";
        name = "Fennec Browser";
        categories = ["Network" "WebBrowser"];
      }
    ];
  };

  xdg.desktopEntries = desktopEntries;
}
