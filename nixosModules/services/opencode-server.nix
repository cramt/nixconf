{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  opencodePkg = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
  cfg = config.myNixOS.services.opencode-server;
  secrets = import ../../secrets.nix;
  port = config.port-selector.ports.opencode-server;

  # Build a Docker image with opencode and dependencies
  dockerImage = pkgs.dockerTools.streamLayeredImage {
    name = "opencode-server";
    tag = "1";
    contents = with pkgs; [
      coreutils
      cacert
      git
      openssh
      opencodePkg
      bash
    ];
    config = {
      Cmd = [
        "${opencodePkg}/bin/opencode"
        "serve"
        "--port"
        "4096"
        "--hostname"
        "0.0.0.0"
      ];
      Env = [
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "HOME=/home/opencode"
      ];
      WorkingDir = "/workspace";
    };
  };
in {
  options.myNixOS.services.opencode-server = {
    workspacePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["/mnt/imbrium/opencode-workspace"];
      description = "Host paths to mount as workspace directories (read-write)";
    };

    configVolume = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/imbrium/configs/opencode-server";
      description = "Persistent config/state directory for opencode";
    };

    sshKeyPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/home/cramt/.ssh";
      description = "Path to SSH keys directory (mounted read-only for git access)";
    };

    gitConfigPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/home/cramt/.gitconfig";
      description = "Path to .gitconfig file (mounted read-only)";
    };

    useGVisor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use gVisor runtime for extra syscall-level sandboxing";
    };

    corsOrigins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional CORS origins to allow for web frontend";
    };
  };

  config = {
    # Auto-assign port
    port-selector.auto-assign = ["opencode-server"];

    # Integrate with Caddy reverse proxy
    myNixOS.services.caddy.serviceMap.opencode = {
      port = port;
      basic-auth = {
        username = "admin";
        hashed-password = "$2a$14$3elBL1TrHKl9Ei10/PqFfudA8v939SirZN1sAynDbsWOE5t.eT3AK";
      };
    };

    # Ensure config directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.configVolume} 0755 root root -"
      "d ${cfg.configVolume}/config 0755 root root -"
      "d ${cfg.configVolume}/data 0755 root root -"
      "d ${cfg.configVolume}/cache 0755 root root -"
    ];

    # Docker container with gVisor sandboxing
    virtualisation.oci-containers.containers.opencode-server = {
      hostname = "opencode-server";
      imageStream = dockerImage;
      image = "opencode-server:1";

      ports = [
        "127.0.0.1:${builtins.toString port}:4096"
      ];

      volumes =
        [
          # Config/state persistence
          "${cfg.configVolume}/config:/home/opencode/.config/opencode"
          "${cfg.configVolume}/data:/home/opencode/.local/share/opencode"
          "${cfg.configVolume}/cache:/home/opencode/.cache/opencode"
        ]
        # Workspace directories (read-write)
        ++ (builtins.map (path: "${path}:${path}:rw") cfg.workspacePaths)
        # SSH keys (read-only for git operations)
        ++ (lib.optionals (cfg.sshKeyPath != null) [
          "${cfg.sshKeyPath}:/home/opencode/.ssh:ro"
        ])
        # Git config (read-only)
        ++ (lib.optionals (cfg.gitConfigPath != null) [
          "${cfg.gitConfigPath}:/home/opencode/.gitconfig:ro"
        ]);

      environment =
        {
          # Git SSH config
          GIT_SSH_COMMAND = "ssh -o StrictHostKeyChecking=accept-new";
          # API keys from secrets
          GEMINI_API_KEY = secrets.gemini_api_key;
        }
        // (lib.optionalAttrs (secrets ? anthropic_api_key) {
          ANTHROPIC_API_KEY = secrets.anthropic_api_key;
        });

      # Use gVisor runtime for sandboxing
      extraOptions = lib.optionals cfg.useGVisor ["--runtime=runsc"];

      autoStart = true;
    };
  };
}
