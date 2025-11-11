{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  port = config.port-selector.ports.searxng;
in {
  config = {
    port-selector.auto-assign = ["searxng"];
    services.searx = {
      enable = true;
      settings = {
        engines = [
          {
            name = "arch wiki";
            engine = "archlinux";
          }
        ];
        search = {
          safe_search = 0;
          autocomplete = "";
          default_lang = "";
          formats = ["json" "html"];
        };
        server = {
          inherit port;
          bind_address = "0.0.0.0";
          secret_key = "";
        };
      };
    };
  };
}
