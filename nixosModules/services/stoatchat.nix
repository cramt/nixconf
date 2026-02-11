{
  config,
  lib,
  ...
}: let
  cfg = config.myNixOS.services.stoatchat;
  port = config.port-selector.ports.stoatchat;
in {
  options.myNixOS.services.stoatchat = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "chat.localhost";
      description = "Domain for the Stoatchat instance.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/stoatchat";
      description = "Directory for persistent data.";
    };
  };

  config = {
    port-selector.set-ports."8380" = "stoatchat";

    services.stoatchat = {
      enable = true;
      domain = cfg.domain;
      inherit (cfg) dataDir;
      inherit port;
      openFirewall = true;
      settings.api.registration.invite_only = true;
    };

    myNixOS.services.caddy.serviceMap.chat = lib.mkIf config.myNixOS.services.caddy.enable {
      inherit port;
      basic-auth = null;
    };
  };
}
