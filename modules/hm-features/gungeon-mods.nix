# Declarative Enter the Gungeon mods (BepInEx, from Thunderstore).
#
# Exists for Auto Reload: vanilla only reloads on a fresh click once the clip is
# empty, so holding fire just stops shooting.
#
# Same activation story as steam-shortcuts: the mod files land every time, the
# launch option only when Steam is down — which boot guarantees. To apply a
# change without rebooting, quit Steam and run `gungeon-mods` (it's on PATH).
{...}: {
  hmModules.features.gungeon-mods = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.gungeon-mods;

    writer = import ../../scripts/gungeon_mods.nix {inherit pkgs;};

    thunderstore = {
      name,
      version,
      hash,
    }:
      pkgs.fetchzip {
        url = "https://thunderstore.io/package/download/${builtins.replaceStrings ["-"] ["/"] name}/${version}/";
        extension = "zip";
        stripRoot = false;
        inherit hash;
      };

    spec = pkgs.writeText "gungeon-mods.json" (builtins.toJSON {
      inherit (cfg) gameDir;
      loader = thunderstore {
        name = "BepInEx-BepInExPack_EtG";
        version = "5.4.2101";
        hash = "sha256-N+otcJkke/enm5RcInTVl25jUjbKu+5iRa67OQG+jBk=";
      };
      mods =
        map (m: {
          inherit (m) name;
          src = thunderstore m;
        })
        cfg.mods;
    });

    apply = pkgs.writeShellScriptBin "gungeon-mods" ''
      exec ${writer}/bin/gungeon-mods ${spec}
    '';
  in {
    options.myHomeManager.gungeon-mods = {
      enable = lib.mkEnableOption "myHomeManager.gungeon-mods";

      gameDir = lib.mkOption {
        type = lib.types.str;
        default = "~/.local/share/Steam/steamapps/common/Enter the Gungeon";
      };

      mods = lib.mkOption {
        description = ''
          Thunderstore packages to install, dependencies included — nothing
          resolves them for you. The BepInEx loader itself is always installed.
        '';
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              example = "TeamPlanetside-Auto_Reload";
              description = "Thunderstore full name, Owner-Package.";
            };
            version = lib.mkOption {type = lib.types.str;};
            hash = lib.mkOption {type = lib.types.str;};
          };
        });
        default = [
          {
            name = "MtG_API-Mod_the_Gungeon_API";
            version = "1.9.2";
            hash = "sha256-RZvvN+/SDyQ2hIBQ0rubQ5CDWSWnBbSwHUZRxkSvnTI=";
          }
          {
            name = "TeamPlanetside-Auto_Reload";
            version = "1.0.0";
            hash = "sha256-YF0b5auxKmhV7aF7c9PqTLUzOz6bJ8Ur0z6KkgOUpNU=";
          }
        ];
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [apply];

      home.activation.gungeon-mods =
        lib.hm.dag.entryAfter ["writeBoundary"] ''
          run ${apply}/bin/gungeon-mods
        '';
    };
  };
}
