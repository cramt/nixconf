# What emrakul's Home lists on ganymede: the desktop entries other files put
# in ganymede.homeApps (web-apps.nix, kdeconnect.nix, moonlight.nix), the ones
# written at run time into ganymede.homeStateDirs (moonlight.nix's Games), and
# nothing else.
{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  homeApps = pkgs.symlinkJoin {
    name = "home-apps";
    paths = config.ganymede.homeApps;
  };
  stateDirs = map (dir: "\${XDG_STATE_HOME:-$HOME/.local/state}/${dir}/share") config.ganymede.homeStateDirs;
in {
  options.ganymede = {
    homeApps = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Packages whose share/applications and share/icons are all Home sees.
        Each entry's Exec has to put the normal XDG_DATA_DIRS back for itself.
      '';
    };

    homeStateDirs = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9._-]+");
      default = [];
      example = ["emrakul-games"];
      description = ''
        Dirs under the user's XDG_STATE_HOME whose share/applications Home
        also lists, for entries a service writes as the session runs. Home
        reads them again every few seconds.
      '';
    };
  };

  # Home lists every desktop entry in XDG_DATA_DIRS, and the system and home
  # profiles carry plenty (nvim, btop, qt5ct, nixos-manual, ...). The TV shows
  # only its apps, so emrakul gets data dirs holding nothing else. Its
  # unit's Environment= can't do this: PAM's login stack sets XDG_DATA_DIRS
  # after it.
  config.services.emrakul.package = let
    emrakul = options.services.emrakul.package.default;
  in
    pkgs.writeShellApplication {
      name = "emrakul";
      text = ''
        XDG_DATA_DIRS="${lib.concatStringsSep ":" (["${homeApps}/share"] ++ stateDirs)}" exec ${lib.getExe emrakul} "$@"
      '';
    };
}
