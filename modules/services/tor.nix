{ ... }: {
  flake.nixosModules."services.tor" = {
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.services.tor;
    port = config.port-selector.ports.tor_socks;
  in {
    options.myNixOS.services.tor = {
      enable = lib.mkEnableOption "myNixOS.services.tor";
    };
    config = lib.mkIf cfg.enable {
      port-selector.auto-assign = ["tor_socks"];
      services.tor = {
        enable = true;
        openFirewall = true;
        settings.SOCKSPort = {
          inherit port;
          addr = "127.0.0.1";
          IsolateDestAddr = false;
        };
      };
    };
  };
}
