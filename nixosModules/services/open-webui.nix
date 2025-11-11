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
  searxng-port = config.port-selector.ports.searxng;
  tika-port = config.port-selector.ports.tika;
in {
  config = {
    myNixOS.services.searxng.enable = true;
    myNixOS.services.tika.enable = true;
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
        RAG_EMBEDDING_ENGINE = "ollama";
        RAG_EMBEDDING_MODEL = "DC1LEX/nomic-embed-text-v1.5-multimodal:latest";
        WEBUI_URL = "https://open-webui.${secrets.domain}";
        ENABLE_OLLAMA_API = "true";
        OLLAMA_BASE_URLS = "http://192.168.178.23:${builtins.toString ollama_port};http://localhost:${builtins.toString ollama_port}";
        ENABLE_PERSISTENT_CONFIG = "false";
        ENABLE_WEB_SEARCH = "true";
        WEB_SEARCH_ENGINE = "searxng";
        SEARXNG_QUERY_URL = "http://localhost:${builtins.toString searxng-port}/search?q=<query>";
      };
    };
  };
}
