{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.myNixOS.services.olla;
  port = config.port-selector.ports.olla;
  docker_source = pkgs.npinsSources."thushan/olla";

  yamlFormat = pkgs.formats.yaml {};

  ollaConfig = yamlFormat.generate "olla-config.yaml" {
    server = {
      host = "0.0.0.0";
      port = 40114;
    };
    proxy = {
      engine = cfg.proxyEngine;
      load_balancer = cfg.loadBalancer;
    };
    discovery = {
      type = "static";
      static.endpoints = cfg.endpoints;
    };
    logging = {
      level = cfg.logLevel;
      format = "json";
      output = "stdout";
    };
  };
in {
  options.myNixOS.services.olla = {
    endpoints = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          url = lib.mkOption {
            type = lib.types.str;
            description = "URL of the backend endpoint";
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "Name for this endpoint";
          };
          type = lib.mkOption {
            type = lib.types.enum ["ollama" "openai" "lmstudio" "vllm" "llamacpp" "litellm" "sglang"];
            default = "ollama";
            description = "Backend type";
          };
          priority = lib.mkOption {
            type = lib.types.int;
            default = 100;
            description = "Priority for priority-based load balancing (higher = preferred)";
          };
        };
      });
      default = [];
      description = "Backend LLM endpoints for olla to proxy and load balance";
    };

    loadBalancer = lib.mkOption {
      type = lib.types.enum ["round-robin" "least-connections" "priority"];
      default = "least-connections";
      description = "Load balancing strategy";
    };

    proxyEngine = lib.mkOption {
      type = lib.types.enum ["sherpa" "olla"];
      default = "olla";
      description = "Proxy engine: olla (circuit breakers, connection pooling) or sherpa (simple)";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum ["debug" "info" "warn" "error"];
      default = "info";
      description = "Log level";
    };
  };

  config = {
    port-selector.auto-assign = ["olla"];

    virtualisation.quadlet.containers.olla = {
      autoStart = true;
      containerConfig = {
        image = "${docker_source.image_name}:${docker_source.image_tag}@${docker_source.image_digest}";
        publishPorts = ["127.0.0.1:${toString port}:40114"];
        volumes = ["${ollaConfig}:/config/config.yaml:ro"];
        environments = {
          OLLA_CONFIG_FILE = "/config/config.yaml";
        };
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "10";
      };
      unitConfig = {
        Description = "Olla LLM load balancer and proxy";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
    };
  };
}
