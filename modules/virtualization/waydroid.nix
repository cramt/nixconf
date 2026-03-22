# Waydroid Android container — NixOS + HM desktop entries
{ ... }: {
  flake.nixosModules."features.waydroid" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.waydroid;
    declaradroid = pkgs.callPackage ../../packages/declaradroid/default.nix {
      waydroid-script = pkgs.nur.repos.ataraxiasjel.waydroid-script;
    };
    configFile = pkgs.writeText "declaradroid-config.json" (builtins.toJSON {
      inherit (cfg) gapps armEmulation properties;
      extras = {
        inherit (cfg.extras) magisk widevine microg smartdock;
      };
      apps = {
        inherit (cfg.apps) fdroid apkpure;
      };
    });
    hmUsers = builtins.attrNames (config.myNixOS.home-users or {});
    hasDesktopEntries = builtins.length cfg.desktopEntries > 0;
    getUserUid = username: config.users.users.${username}.uid or null;
    userUids = builtins.filter (uid: uid != null) (map getUserUid hmUsers);
  in {
    options.myNixOS.waydroid = {
      enable = lib.mkEnableOption "myNixOS.waydroid";
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
        description = "Waydroid properties to set.";
      };
      extras = {
        magisk = lib.mkOption { type = lib.types.bool; default = false; description = "Install Magisk for root access."; };
        widevine = lib.mkOption { type = lib.types.bool; default = false; description = "Install Widevine DRM (L3)."; };
        microg = lib.mkOption { type = lib.types.bool; default = false; description = "Install microG."; };
        smartdock = lib.mkOption { type = lib.types.bool; default = false; description = "Install SmartDock."; };
      };
      apps = {
        fdroid = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "F-Droid packages to install."; };
        apkpure = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "APKPure packages to install."; };
      };
      desktopEntries = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            id = lib.mkOption { type = lib.types.str; description = "Android package ID"; };
            name = lib.mkOption { type = lib.types.str; description = "Display name"; };
            comment = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
            icon = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
            categories = lib.mkOption { type = lib.types.listOf lib.types.str; default = ["Application"]; };
          };
        });
        default = [];
        description = "Desktop entries to create for Waydroid apps.";
      };
    };

    config = lib.mkIf cfg.enable {
      networking.nftables.enable = true;
      virtualisation.waydroid.enable = true;
      systemd.tmpfiles.rules = map (uid:
        "L+ /run/user/${toString uid}/pulse/native - - - - /var/run/pulse/native"
      ) userUids;
      environment.systemPackages =
        [
          declaradroid
          pkgs.nur.repos.ataraxiasjel.waydroid-script
          pkgs.apkeep
          pkgs.fdroidcl
          pkgs.iptables-nftables-compat
          pkgs.android-tools
        ]
        ++ map
        (entry: let
          scriptName = builtins.replaceStrings ["."] ["-"] entry.id;
        in
          pkgs.writeShellScriptBin "waydroid-${scriptName}" ''
            set -e
            if ! waydroid status 2>/dev/null | grep -q "Session:.*RUNNING"; then
              echo "Starting Waydroid session..."
              waydroid session start &
              sleep 5
            fi
            echo "Launching ${entry.name} (${entry.id})..."
            exec waydroid app launch ${entry.id} "$@"
          '')
        cfg.desktopEntries
        ++ map
        (entry:
          pkgs.makeDesktopItem {
            name = "waydroid-${entry.id}";
            desktopName = entry.name;
            comment = if entry.comment != null then entry.comment else "Android app running in Waydroid";
            exec = "${pkgs.waydroid}/bin/waydroid app launch ${entry.id}";
            icon = if entry.icon != null then entry.icon else "waydroid";
            categories = entry.categories;
            startupWMClass = "Waydroid";
            terminal = false;
          })
        cfg.desktopEntries;
      system.activationScripts.declaradroid = lib.stringAfter ["var"] ''
        echo "Applying Declaradroid configuration..."
        ${declaradroid}/bin/declaradroid apply ${configFile} || true
      '';
      home-manager.users = lib.mkIf hasDesktopEntries (
        lib.genAttrs hmUsers (_: {
          myHomeManager.waydroid = {
            enable = true;
            apps = cfg.desktopEntries;
          };
        })
      );
    };
  };

  hmModules.features.waydroid = { config, lib, pkgs, ... }:
  let
    cfg = config.myHomeManager.waydroid;
    makeDesktopEntry = app: {
      name = "waydroid-${app.id}";
      value = {
        name = app.name;
        comment = if app.comment != null then app.comment else "Android app running in Waydroid";
        exec = "${pkgs.waydroid}/bin/waydroid app launch ${app.id}";
        icon = if app.icon != null then app.icon else "waydroid";
        terminal = false;
        type = "Application";
        categories = app.categories;
        settings.StartupWMClass = "Waydroid";
      };
    };
    desktopEntries = builtins.listToAttrs (map makeDesktopEntry cfg.apps);
  in {
    options.myHomeManager.waydroid = {
      enable = lib.mkEnableOption "myHomeManager.waydroid";
      apps = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            id = lib.mkOption { type = lib.types.str; description = "Android package ID"; };
            name = lib.mkOption { type = lib.types.str; description = "Display name"; };
            comment = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
            icon = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
            categories = lib.mkOption { type = lib.types.listOf lib.types.str; default = ["Application"]; };
          };
        });
        default = [];
        description = "List of Waydroid apps to create desktop entries for.";
      };
    };
    config = lib.mkIf cfg.enable {
      xdg.desktopEntries = desktopEntries;
    };
  };
}
