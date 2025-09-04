{
  pkgs,
  inputs,
  config,
  lib,
  ...
}: let
  foundryvttPkg = inputs.foundryvtt.packages.${pkgs.system}.foundryvtt_12.overrideAttrs {
    build = "331";
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
    port-selector.services.foundry = {};
    services.foundryvtt = {
      enable = true;
      port = config.port-selector.ports.foundry.port;
      dataDir = cfg.dataVolume;
      #world = "magy-mage";
      hostName = "foundry-a.${(import ../../secrets.nix).domain}";
      minifyStaticFiles = true;
      proxyPort = 443;
      proxySSL = true;
      package = foundryvttPkg;
    };
  };
}
