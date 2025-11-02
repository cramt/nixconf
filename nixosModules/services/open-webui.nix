{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  port = config.port-selector.ports.open-webui;

  secrets = import ../../secrets.nix;
  ollama_port = config.port-selector.ports.ollama;
in {
  config = {
    myNixOS.services.caddy.serviceMap = {
      open-webui = {
        port = port;
      };
    };
    port-selector.auto-assign = ["open-webui"];
    services.open-webui = {
      enable = true;
      port = port;
      environment = {
        WEBUI_URL = "https://open-webui.${secrets.domain}";
        ENABLE_OLLAMA_API = "true";
        OLLAMA_BASE_URLS = "http://192.168.178.23:${builtins.toString ollama_port};http://localhost:${builtins.toString ollama_port}";
        ENABLE_PERSISTENT_CONFIG = "false";
      };
    };
  };
}
