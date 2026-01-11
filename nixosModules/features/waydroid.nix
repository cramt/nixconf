# Waydroid NixOS module using Declaradroid
# This is a thin wrapper that integrates with the myNixOS module system
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.waydroid;

  # Build declaradroid package
  declaradroid = pkgs.callPackage ../../packages/declaradroid/default.nix {
    waydroid-script = pkgs.nur.repos.ataraxiasjel.waydroid-script;
  };

  # Generate the JSON config file
  configFile = pkgs.writeText "declaradroid-config.json" (builtins.toJSON {
    inherit (cfg) gapps armEmulation properties;
    extras = {
      inherit (cfg.extras) magisk widevine microg smartdock;
    };
    apps = {
      inherit (cfg.apps) fdroid apkpure;
    };
  });

  # Users that have home-manager enabled
  hmUsers = builtins.attrNames (config.myNixOS.home-users or {});
  hasDesktopEntries = builtins.length cfg.desktopEntries > 0;

  # Get UIDs for all home-manager users
  getUserUid = username: config.users.users.${username}.uid or null;
  userUids = builtins.filter (uid: uid != null) (map getUserUid hmUsers);
in {
  options.myNixOS.waydroid = {
    gapps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to install Google Apps (GApps) in the Waydroid container.";
    };

    armEmulation = lib.mkOption {
      type = lib.types.enum [false "libndk" "libhoudini"];
      default = false;
      description = ''
        ARM emulation for running ARM apps on x86_64.
        - false: No ARM emulation
        - "libndk": Use libndk (better for AMD CPUs)
        - "libhoudini": Use libhoudini (better for Intel CPUs)
      '';
    };

    properties = lib.mkOption {
      type = lib.types.attrsOf (lib.types.oneOf [lib.types.bool lib.types.int lib.types.str (lib.types.listOf lib.types.str)]);
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
      magisk = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install Magisk for root access with Zygisk support.";
      };

      widevine = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install Widevine DRM (L3) support for streaming services.";
      };

      microg = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install microG (FOSS Google Play Services replacement).";
      };

      smartdock = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install SmartDock for desktop-mode dock.";
      };
    };

    apps = {
      fdroid = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["org.mozilla.fennec_fdroid" "com.termux" "org.videolan.vlc"];
        description = "List of F-Droid package IDs to install in Waydroid.";
      };

      apkpure = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["com.instagram.android" "com.whatsapp"];
        description = "List of package IDs to install from APKPure (no authentication required).";
      };
    };

    desktopEntries = lib.mkOption {
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
      description = "Desktop entries to create for Waydroid apps (applied to all home-manager users).";
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

  config = {
    networking.nftables.enable = true;
    virtualisation.waydroid.enable = true;

    # Create symlink for PulseAudio socket in user runtime directories
    # PipeWire's PulseAudio socket is at /var/run/pulse/native (system-wide)
    # but Waydroid expects it at /run/user/<uid>/pulse/native
    systemd.tmpfiles.rules = map (uid:
      "L+ /run/user/${toString uid}/pulse/native - - - - /var/run/pulse/native"
    ) userUids;

    # Ensure iptables compatibility layer is available for waydroid/lxc
    # The zen kernel uses nftables, but waydroid calls legacy iptables
    environment.systemPackages =
      [
        declaradroid
        pkgs.nur.repos.ataraxiasjel.waydroid-script
        pkgs.apkeep
        pkgs.fdroidcl
        pkgs.iptables-nftables-compat # Provides iptables command using nftables backend
        pkgs.android-tools # For adb, needed to install split APKs
      ]
      # CLI wrapper scripts for each app (for debugging)
      ++ map
      (entry: let
        scriptName = builtins.replaceStrings ["."] ["-"] entry.id;
      in
        pkgs.writeShellScriptBin "waydroid-${scriptName}" ''
          set -e
          
          # Check if waydroid session is running
          if ! waydroid status 2>/dev/null | grep -q "Session:.*RUNNING"; then
            echo "Starting Waydroid session..."
            waydroid session start &
            sleep 5
          fi
          
          echo "Launching ${entry.name} (${entry.id})..."
          exec waydroid app launch ${entry.id} "$@"
        '')
      cfg.desktopEntries
      # Desktop entries for each app
      ++ map
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

    # Activation script to apply declaradroid configuration
    system.activationScripts.declaradroid = lib.stringAfter ["var"] ''
      echo "Applying Declaradroid configuration..."
      ${declaradroid}/bin/declaradroid apply ${configFile} || true
    '';

    # Pass desktop entries to home-manager users
    home-manager.users = lib.mkIf hasDesktopEntries (
      lib.genAttrs hmUsers (_: {
        myHomeManager.waydroid = {
          enable = true;
          apps = cfg.desktopEntries;
        };
      })
    );
  };
}
