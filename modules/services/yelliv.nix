# yelliv — OpenClaw gateway running in an isolated NixOS container that
# talks to the host's llama-cpp HTTP API.
{ inputs, ... }: {
  flake.nixosModules."services.yelliv" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.services.yelliv;
    hostAddress = "10.233.42.1";
    localAddress = "10.233.42.2";
    gatewayPort = 18789;
  in {
    options.myNixOS.services.yelliv = {
      enable = lib.mkEnableOption "myNixOS.services.yelliv";
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/yelliv";
        description = "Host state dir bind-mounted into the container at /var/lib/openclaw";
      };
      documentsDir = lib.mkOption {
        type = lib.types.path;
        default = ../../yelliv-documents;
        description = "Directory with AGENTS/SOUL/TOOLS documents; bind-mounted read-only";
      };
      llamaBaseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://${hostAddress}:11434/v1";
        description = "OpenAI-compatible base URL for the host's llama-cpp instance";
      };
      llamaModelId = lib.mkOption {
        type = lib.types.str;
        default = "qwen3.6-27b";
        description = "Model id exposed by llama-swap on the host";
      };
      hostPort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "Host port forwarded to the gateway (null = auto via port-selector)";
      };
    };
    config = lib.mkIf cfg.enable (let
      resolvedHostPort =
        if cfg.hostPort != null
        then cfg.hostPort
        else config.port-selector.ports.yelliv;
    in {
      port-selector.auto-assign = lib.optional (cfg.hostPort == null) "yelliv";
      port-selector.set-ports = lib.optionalAttrs (cfg.hostPort != null) {
        "${toString cfg.hostPort}" = "yelliv";
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 root root -"
      ];

      # Allow the container to reach the host's llama-cpp port.
      networking.firewall.interfaces."ve-yelliv".allowedTCPPorts = [ 11434 ];
      networking.firewall.allowedTCPPorts = [ resolvedHostPort ];

      containers.yelliv = {
        autoStart = true;
        ephemeral = false;
        privateNetwork = true;
        inherit hostAddress localAddress;
        forwardPorts = [{
          hostPort = resolvedHostPort;
          containerPort = gatewayPort;
          protocol = "tcp";
        }];
        bindMounts = {
          "/etc/yelliv/documents" = {
            hostPath = "${cfg.documentsDir}";
            isReadOnly = true;
          };
          "/var/lib/openclaw" = {
            hostPath = cfg.dataDir;
            isReadOnly = false;
          };
        };
        config = { config, lib, pkgs, ... }: {
          system.stateVersion = "25.11";

          imports = [
            inputs.nix-openclaw.nixosModules.openclaw-gateway
          ];

          nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];
          nixpkgs.config.allowUnfree = true;

          networking.firewall.allowedTCPPorts = [ gatewayPort ];
          networking.useHostResolvConf = lib.mkForce false;
          services.resolved.enable = true;

          # Mirror gateway stdout/stderr to the journal so the host can
          # `journalctl --machine=yelliv -u openclaw-gateway` without chasing
          # the log file inside the state dir.
          systemd.services.openclaw-gateway.serviceConfig = {
            StandardOutput = lib.mkForce "journal";
            StandardError = lib.mkForce "journal";
          };

          services.openclaw-gateway = {
            enable = true;
            port = gatewayPort;
            stateDir = "/var/lib/openclaw";
            config = {
              gateway = {
                mode = "local";
                bind = "custom";
                customBindHost = "0.0.0.0";
                auth.mode = "none";
              };
              models = {
                mode = "merge";
                providers.saturn-llama-cpp = {
                  api = "openai-completions";
                  baseUrl = cfg.llamaBaseUrl;
                  models = [{
                    id = cfg.llamaModelId;
                    name = cfg.llamaModelId;
                  }];
                };
              };
              agents.defaults.workspace = "/etc/yelliv/documents";
            };
          };
        };
      };

    });
  };
}
