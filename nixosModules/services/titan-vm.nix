{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  cfg = config.myNixOS.services.titan-vm;
  secrets = import ../../secrets.nix;

  # Get the titan NixOS configuration and build the VM runner
  titanConfig = inputs.self.nixosConfigurations.titan;
  titanVm = titanConfig.config.system.build.vm;
  
  titanFrontendPackage = pkgs.callPackage ../../titan-frontend/default.nix {};

  # Get ports from port-selector (localhost only)
  sshPort = config.port-selector.ports.titan-vm-ssh;
  vncPort = config.port-selector.ports.titan-vm-vnc;
in {
  options.myNixOS.services.titan-vm = {
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/titan-vm";
      description = "Directory to store VM disk images and state";
    };
    memory = lib.mkOption {
      type = lib.types.str;
      default = "4G";
      description = "Amount of RAM for the VM";
    };
    cores = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Number of CPU cores for the VM";
    };
    diskSize = lib.mkOption {
      type = lib.types.str;
      default = "50G";
      description = "Size of the VM disk image";
    };
    
    frontend = {
      enable = lib.mkEnableOption "Titan VM Frontend API";
    };
  };

  config = {
    # Register ports with port-selector
    port-selector.auto-assign = [
      "titan-vm-ssh"
      "titan-vm-vnc"
    ] ++ lib.optional cfg.frontend.enable "titan-frontend";

    # Ensure QEMU/KVM is available
    virtualisation.libvirtd.enable = true;

    environment.systemPackages = [
      titanVm
      pkgs.qemu
      # SSH helper script
      (pkgs.writeShellScriptBin "ssh_titan" ''
        exec ${pkgs.openssh}/bin/ssh -p ${toString sshPort} "$@" 127.0.0.1
      '')
    ];

    # Create data directory for persistent disk
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    # Main VM service using NixOS's built-in VM runner
    # All ports bound to localhost only - not accessible from outside
    systemd.services.titan-vm = {
      description = "Titan NixOS VM for LLM agents";
      after = ["network.target" "libvirtd.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        # NixOS VM runner uses these environment variables
        # QEMU_OPTS for general options
        QEMU_OPTS = lib.concatStringsSep " " [
          "-m ${cfg.memory}"
          "-smp ${toString cfg.cores}"
          "-vnc 127.0.0.1:${toString (vncPort - 5900)}"
        ];
        # QEMU_NET_OPTS configures the existing user network (appended to -netdev user,id=user.0)
        QEMU_NET_OPTS = "hostfwd=tcp:127.0.0.1:${toString sshPort}-:22";
        NIX_DISK_IMAGE = "${cfg.dataDir}/titan.qcow2";
        USE_TMPDIR = "0";
      };

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${titanVm}/bin/run-titan-vm";
      };
    };
    
    # Frontend Service
    systemd.services.titan-frontend = lib.mkIf cfg.frontend.enable {
      description = "Titan VM Frontend API";
      after = ["network.target" "titan-vm.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        PORT = toString config.port-selector.ports.titan-frontend;
        HOST = "0.0.0.0";
        SSH_HOST = "127.0.0.1";
        SSH_PORT = toString sshPort;
        VNC_HOST = "127.0.0.1";
        VNC_PORT = toString vncPort;
        SSH_USERNAME = "cramt";
        SSH_PASSWORD = "titan";
        TITAN_API_KEY = secrets.titan_frontend_api_key or "default-dev-key";
      };

      serviceConfig = {
        ExecStart = "${titanFrontendPackage}/bin/titan-frontend";
        Restart = "always";
        RestartSec = "10";
        User = "cramt";
      };
    };

    myNixOS.services.caddy.serviceMap.titan-frontend = lib.mkIf cfg.frontend.enable {
      port = config.port-selector.ports.titan-frontend;
    };
  };
}
