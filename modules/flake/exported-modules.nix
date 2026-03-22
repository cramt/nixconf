# Legacy auto-discovery bridge for home-manager modules.
# NixOS modules have been fully migrated to dendritic modules.
# HM modules in homeManagerModules/ are still auto-discovered here.
{lib, myLib, ...}: let
  extendDirNested = optionPrefix: dir:
    let files = myLib.filesIn dir;
    in builtins.listToAttrs (map (f: let
        name = myLib.fileNameOf f;
      in {
        name = name;
        value = myLib.mkEnabledModule
          (optionPrefix ++ [name])
          (builtins.concatStringsSep "." (optionPrefix ++ [name]))
          f;
      })
      files);

  hmFeatures = extendDirNested ["myHomeManager"]           ../../homeManagerModules/features;
  hmBundles  = extendDirNested ["myHomeManager" "bundles"] ../../homeManagerModules/bundles;
in {
  hmModules = {
    features = hmFeatures;
    bundles = hmBundles;
  };
}
