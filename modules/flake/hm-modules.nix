# Typed accumulator for home-manager modules.
#
# flake-parts' flake.nixosModules is lazyAttrsOf deferredModule and merges
# naturally across module files.  flake.homeManagerModules, however, is
# freeform (raw) and does NOT merge — two definitions would conflict.
#
# This module provides properly-typed options that any flake-parts module can
# contribute to.  The final attrsets are wired into flake.homeManagerModules
# once, avoiding merge conflicts.
{ lib, config, ... }: {
  options.hmModules = {
    default = lib.mkOption {
      type = lib.types.deferredModule;
      description = "The base home-manager module (homeManagerModules.default)";
    };
    features = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
      description = "Accumulated home-manager feature modules";
    };
    bundles = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
      description = "Accumulated home-manager bundle modules";
    };
  };

  config.flake.homeManagerModules = {
    default = config.hmModules.default;
    features = config.hmModules.features;
    bundles = config.hmModules.bundles;
  };
}
