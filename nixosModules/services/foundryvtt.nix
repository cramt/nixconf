{
  pkgs,
  inputs,
  config,
  lib,
  ...
}: let
  version = "12.0.0+331";
  foundryvttPkg = inputs.foundryvtt.packages.${pkgs.system}.foundryvtt_12.overrideAttrs {
    version = version;
  };
  cfg = config.myNixOS.services.foundryvtt;
in {
  options.myNixOS.services.foundryvtt = {
    dataVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the foundry data
      '';
    };
  };
  config = {
    services.foundryvtt = {
      enable = true;
      port = 30000;
      dataDir = cfg.dataVolume;
      world = "magy-mage";
      hostName = "foundry-a.${(import ../../secrets.nix).domain}";
      minifyStaticFiles = true;
      proxyPort = 443;
      proxySSL = true;
      package = foundryvttPkg;
    };
  };
}
