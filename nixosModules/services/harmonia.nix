{
  lib,
  config,
  ...
}: let
  cfg = config.myNixOS.services.harmonia;
  port = config.port-selector.ports.harmonia;
in {
  options.myNixOS.services.harmonia = {
    prio = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = ''
        prio for this cache
      '';
    };
  };
  config = {
    port-selector.auto-assign = ["harmonia"];
    myNixOS.services.caddy.serviceMap.nix-store.port = port;
    services.harmonia = {
      enable = true;
      settings = {
        bind = "0.0.0.0:${builtins.toString port}";
        priority = cfg.prio;
      };
    };
  };
}
