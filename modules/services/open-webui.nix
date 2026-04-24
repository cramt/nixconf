{ ... }: {
  flake.nixosModules."services.open-webui" = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.myNixOS.services.open-webui;
    port = config.port-selector.ports.open-webui;
    site = import ../../myLib/site.nix;
    searxng-port = config.port-selector.ports.searxng;
    tika-port = config.port-selector.ports.tika;
  in {
    options.myNixOS.services.open-webui = {
      enable = lib.mkEnableOption "myNixOS.services.open-webui";
    };
    config = lib.mkIf cfg.enable {
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
          CONTENT_EXTRACTION_ENGINE = "tika";
          TIKA_SERVER_URL = "http://localhost:${builtins.toString tika-port}";
          RAG_TEXT_SPLITTER = "token";
          CHUNK_SIZE = "500";
          CHUNK_OVERLAP = "50";
          WEBUI_URL = "https://open-webui.${site.domain}";
          ENABLE_OLLAMA_API = "false";
          ENABLE_OPENAI_API = "true";
          OPENAI_API_BASE_URLS = "http://192.168.178.23:11434/v1";
          OPENAI_API_KEYS = "none";
          ENABLE_PERSISTENT_CONFIG = "false";
          ENABLE_WEB_SEARCH = "true";
          WEB_SEARCH_ENGINE = "searxng";
          SEARXNG_QUERY_URL = "http://localhost:${builtins.toString searxng-port}/search?q=<query>";
        };
      };
    };
  };
}
