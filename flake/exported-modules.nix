{lib, myLib, ...}: let
  # flake-parts wraps each nixosModules entry as a single NixOS module
  # (type = lazyAttrsOf deferredModule, apply adds _class/_file/imports)
  # So nixosModules entries must be individual modules with flat names.
  extendDirFlat = optionPrefix: namePrefix: dir:
    builtins.listToAttrs (map (f: let
        name = myLib.fileNameOf f;
      in {
        name = namePrefix + name;
        value = myLib.mkEnabledModule
          (optionPrefix ++ [name])
          (builtins.concatStringsSep "." (optionPrefix ++ [name]))
          f;
      })
      (myLib.filesIn dir));

  # homeManagerModules is freeform (not wrapped by flake-parts), so we can
  # use nested attrsets here.
  extendDirNested = optionPrefix: dir:
    builtins.listToAttrs (map (f: let
        name = myLib.fileNameOf f;
      in {
        name = name;
        value = myLib.mkEnabledModule
          (optionPrefix ++ [name])
          (builtins.concatStringsSep "." (optionPrefix ++ [name]))
          f;
      })
      (myLib.filesIn dir));

  nixosFeatures = extendDirFlat ["myNixOS"]            "features." ../nixosModules/features;
  nixosBundles  = extendDirFlat ["myNixOS" "bundles"]  "bundles."  ../nixosModules/bundles;
  nixosServices = extendDirFlat ["myNixOS" "services"] "services." ../nixosModules/services;

  hmFeatures = extendDirNested ["myHomeManager"]           ../homeManagerModules/features;
  hmBundles  = extendDirNested ["myHomeManager" "bundles"] ../homeManagerModules/bundles;
in {
  flake = {
    # Each entry is an individual NixOS module (flake-parts wraps them).
    # Features: "features.<name>", Bundles: "bundles.<name>", Services: "services.<name>"
    nixosModules =
      {default = ../nixosModules;}
      // nixosFeatures
      // nixosBundles
      // nixosServices;

    # Passed through as raw attrsets (flake-parts has no special handling).
    homeManagerModules = {
      default = ../homeManagerModules;
      features = hmFeatures;
      bundles = hmBundles;
    };
  };
}
