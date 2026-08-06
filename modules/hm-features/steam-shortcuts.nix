# Declarative non-Steam shortcuts.
#
# Adding a non-Steam game is normally a click-path through Big Picture that
# writes a binary blob into the Steam profile, which makes the couch machine's
# app list the one bit of it that isn't in the repo. This puts it back.
#
# Nix owns shortcuts.vdf outright — see scripts/steam_shortcuts.nix for why it
# regenerates the file rather than symlinking it, and for what that means for
# shortcuts added by hand.
#
# Two things have to be true for an activation to actually land, and the script
# says which one failed rather than pretending it worked:
#   - Steam must have been logged into once, since the per-account userdata
#     directory doesn't exist before that.
#   - Steam must not be running, because it rewrites the file from memory when
#     it exits. Note that modules/gaming/steam.nix starts Steam at login via
#     steam_background, so on a machine using that, applying a *change* means
#     stopping Steam and re-running `steam-shortcuts` (it's on PATH).
{...}: {
  hmModules.features.steam-shortcuts = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.steam-shortcuts;

    writer = import ../../scripts/steam_shortcuts.nix {inherit pkgs;};

    spec = pkgs.writeText "steam-shortcuts.json" (
      builtins.toJSON (
        lib.mapAttrsToList (name: s: {
          inherit name;
          inherit (s) exe icon launchOptions tags;
          startDir =
            if s.startDir != null
            then s.startDir
            else builtins.dirOf s.exe;
        })
        cfg.shortcuts
      )
    );

    # The spec baked in, so re-applying by hand after a first Steam login is
    # just `steam-shortcuts` with no arguments.
    apply = pkgs.writeShellScriptBin "steam-shortcuts" ''
      exec ${writer}/bin/steam-shortcuts ${spec}
    '';
  in {
    options.myHomeManager.steam-shortcuts = {
      enable = lib.mkEnableOption "myHomeManager.steam-shortcuts";

      shortcuts = lib.mkOption {
        default = {};
        description = ''
          Non-Steam games to declare. The attribute name is the display name
          shown in the Steam library.

          The list is authoritative: anything not declared here is dropped from
          shortcuts.vdf on the next activation.
        '';
        example = lib.literalExpression ''
          {
            "YouTube".exe = "''${pkgs.foo}/bin/couch-youtube";
          }
        '';
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            exe = lib.mkOption {
              type = lib.types.str;
              description = "Absolute path to the executable to launch.";
            };
            startDir = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Working directory. Defaults to the executable's directory.";
            };
            icon = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Absolute path to an icon. Steam falls back to a generic one when empty.";
            };
            launchOptions = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Extra arguments, in Steam's %command% form.";
            };
            tags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Library categories to file the shortcut under.";
            };
          };
        });
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [apply];

      home.activation.steam-shortcuts =
        lib.hm.dag.entryAfter ["writeBoundary"] ''
          run ${apply}/bin/steam-shortcuts
        '';
    };
  };
}
