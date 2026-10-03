# What emrakul's Home lists on ganymede: the desktop entries other files put
# in ganymede.homeApps (web-apps.nix, kdeconnect.nix), and nothing else.
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
in {
  options.ganymede.homeApps = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [];
    description = ''
      Packages whose share/applications and share/icons are all Home sees.
      Each entry's Exec has to put the normal XDG_DATA_DIRS back for itself.
    '';
  };

  # Home lists every desktop entry in XDG_DATA_DIRS, and the system and home
  # profiles carry plenty (nvim, btop, qt5ct, nixos-manual, ...). The TV shows
  # only its apps, so emrakul gets a data dir holding nothing else. Its
  # unit's Environment= can't do this: PAM's login stack sets XDG_DATA_DIRS
  # after it.
  config.services.emrakul.package = let
    emrakul = options.services.emrakul.package.default;
  in
    pkgs.writeShellApplication {
      name = "emrakul";
      text = ''
        XDG_DATA_DIRS=${homeApps}/share exec ${lib.getExe emrakul} "$@"
      '';
    };
}
