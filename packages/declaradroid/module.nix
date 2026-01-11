# Declaradroid NixOS Module
# Declarative Android app management for Waydroid
#
# Usage:
#   imports = [ ./path/to/declaradroid/module.nix ];
#
#   services.declaradroid = {
#     enable = true;
#     gapps = false;
#     armEmulation = true;
#     apps = {
#       fdroid = [ "org.mozilla.fennec_fdroid" ];
#       apkpure = [ "com.microsoft.teams" ];
#     };
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.declaradroid;

  # Build declaradroid package
  declaradroid = pkgs.callPackage ./default.nix {
    waydroid-script = pkgs.nur.repos.ataraxiasjel.waydroid-script or null;
  };

  # Generate the JSON config file
  configFile = pkgs.writeText "declaradroid-config.json" (builtins.toJSON {
    inherit (cfg) gapps armEmulation properties extras;
    apps = {
      inherit (cfg.apps) fdroid apkpure;
    };
  });

  # Desktop entry submodule
  desktopEntryModule = types.submodule {
    options = {
      id = mkOption {
        type = types.str;
        description = "Android package ID (e.g., com.microsoft.teams)";
        example = "com.microsoft.teams";
      };

      name = mkOption {
        type = types.str;
        description = "Display name for the desktop entry";
        example = "Microsoft Teams";
      };

      comment = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Description/comment for the desktop entry";
        example = "Chat and collaboration app";
      };

      icon = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Icon name or path. Defaults to 'waydroid' if not specified.";
        example = "teams";
      };

      categories = mkOption {
        type = types.listOf types.str;
        default = ["Application"];
        description = "Desktop entry categories";
        example = ["Network" "Chat"];
      };
    };
  };
in {
  options.services.declaradroid = {
    enable = mkEnableOption "Declaradroid - declarative Waydroid management";

    gapps = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to install Google Apps (GApps) in the Waydroid container.";
    };

    armEmulation = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable ARM emulation (libndk) for running ARM apps on x86_64.";
    };

    properties = mkOption {
      type = types.attrsOf (types.oneOf [types.bool types.int types.str (types.listOf types.str)]);
      default = {};
      example = {
        multi_windows = true;
        width = 1920;
        height = 1080;
        fake_touch = ["com.game.*" "com.android.chrome"];
        suspend = false;
      };
      description = ''
        Waydroid properties to set. Keys can be short names (e.g., "multi_windows")
        or full property names (e.g., "persist.waydroid.multi_windows").

        Available properties:
        - multi_windows: Enable/disable desktop window integration
        - width/height: Override display dimensions
        - width_padding/height_padding: Adjust padding
        - suspend: Allow container to sleep when no apps active
        - uevent: Allow direct access to hotplugged devices
        - reverse_scrolling: Invert scroll direction
        - fake_touch: List of packages where mouse acts as touch
        - fake_wifi: List of packages that always appear wifi-connected
        - invert_colors: Swap RGBA/BGRA color space
      '';
    };

    extras = {
      magisk = mkOption {
        type = types.bool;
        default = false;
        description = "Install Magisk for root access with Zygisk support.";
      };

      widevine = mkOption {
        type = types.bool;
        default = false;
        description = "Install Widevine DRM (L3) support for streaming services.";
      };

      microg = mkOption {
        type = types.bool;
        default = false;
        description = "Install microG (FOSS Google Play Services replacement).";
      };

      smartdock = mkOption {
        type = types.bool;
        default = false;
        description = "Install SmartDock for desktop-mode dock.";
      };
    };

    apps = {
      fdroid = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["org.mozilla.fennec_fdroid" "com.termux" "org.videolan.vlc"];
        description = "List of F-Droid package IDs to install in Waydroid.";
      };

      apkpure = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["com.instagram.android" "com.whatsapp"];
        description = "List of package IDs to install from APKPure (no authentication required).";
      };
    };

    desktopEntries = mkOption {
      type = types.listOf desktopEntryModule;
      default = [];
      description = "Desktop entries to create for Waydroid apps.";
      example = [
        {
          id = "com.microsoft.teams";
          name = "Microsoft Teams";
          comment = "Chat and collaboration";
          categories = ["Network" "Chat" "Office"];
        }
      ];
    };
  };

  config = mkIf cfg.enable {
    # Enable waydroid
    virtualisation.waydroid.enable = true;

    # Install declaradroid and waydroid-script
    environment.systemPackages = [
      declaradroid
      pkgs.apkeep
      pkgs.fdroidcl
    ] ++ optional (pkgs ? nur.repos.ataraxiasjel.waydroid-script)
      pkgs.nur.repos.ataraxiasjel.waydroid-script;

    # Systemd service to apply configuration
    # Runs after waydroid-container is available but requires manual trigger
    # because waydroid-script needs an active session for some operations
    systemd.services.declaradroid-apply = {
      description = "Apply Declaradroid configuration";
      after = ["waydroid-container.service"];
      wants = ["waydroid-container.service"];
      path = [declaradroid pkgs.waydroid];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${declaradroid}/bin/declaradroid apply ${configFile}";
        RemainAfterExit = true;
      };

      # Don't start automatically - user should start waydroid first
      wantedBy = [];
    };

    # Create desktop entries for configured apps
    environment.etc = listToAttrs (map (entry: {
      name = "xdg/autostart/waydroid-${entry.id}.desktop";
      value.text = ''
        [Desktop Entry]
        Type=Application
        Name=${entry.name}
        ${optionalString (entry.comment != null) "Comment=${entry.comment}"}
        Exec=${pkgs.waydroid}/bin/waydroid app launch ${entry.id}
        Icon=${if entry.icon != null then entry.icon else "waydroid"}
        Categories=${concatStringsSep ";" entry.categories};
        StartupWMClass=Waydroid
        Terminal=false
      '';
    }) cfg.desktopEntries);

    # Also create in applications directory
    environment.systemPackages =
      map
      (entry:
        pkgs.makeDesktopItem {
          name = "waydroid-${entry.id}";
          desktopName = entry.name;
          comment =
            if entry.comment != null
            then entry.comment
            else "Android app running in Waydroid";
          exec = "${pkgs.waydroid}/bin/waydroid app launch ${entry.id}";
          icon =
            if entry.icon != null
            then entry.icon
            else "waydroid";
          categories = entry.categories;
          startupWMClass = "Waydroid";
          terminal = false;
        })
      cfg.desktopEntries;
  };
}
