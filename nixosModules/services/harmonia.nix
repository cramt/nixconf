{ lib, config, ... }:
let

  cfg = config.myNixOS.services.harmonia;
in
{
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
    services.harmonia = {
      enable = true;
      settings = {
        bind = "0.0.0.0:5000";
        priority = cfg.prio;
      };
    };
    networking.firewall.allowedTCPPorts = [ 5000 ];
  };
}
