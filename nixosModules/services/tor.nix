{config, ...}: let
  port = config.port-selector.ports.tor_socks;
in {
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
}
