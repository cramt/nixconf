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
  port = config.port-selector.ports.foundry;
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
    myNixOS.services.caddy.serviceMap.foundry-a.port = port;
    port-selector.auto-assign = ["foundry"];
    services.foundryvtt = {
      enable = true;
      port = port;
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
