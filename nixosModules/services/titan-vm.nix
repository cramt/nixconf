{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  cfg = config.myNixOS.services.titan-vm;
  vmConfig = inputs.self.nixosConfigurations.titan;
  vm = vmConfig.config.system.build.vm;
  port = config.port-selector.ports.titan-vm;
  sshPort = config.port-selector.ports.titan-vm-ssh;
  ttydPort = config.port-selector.ports.titan-vm-ttyd;
  secretsStaging = "${cfg.dataDir}/secrets";
in {
  options.myNixOS.services.titan-vm = {
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/titan-vm";
      description = "Directory to store VM disk image and state";
    };
    memory = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "Amount of RAM for the VM";
    };
    cores = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Number of CPU cores for the VM";
    };
    secretFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = ''
        Attrset of filename -> host path. Each file is copied into a staging
        directory shared into the VM via 9p at /run/openclaw-secrets.
        Only these specific files are visible inside the VM.
      '';
      example = {
        "env" = "/var/lib/opnix/secrets/openclawEnv";
      };
    };
  };

  config = {
    port-selector.auto-assign = ["titan-vm" "titan-vm-ttyd"];
    port-selector.set-ports."2221" = "titan-vm-ssh";

    virtualisation.libvirtd.enable = true;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${secretsStaging} 0700 root root -"
    ];

    systemd.services.titan-vm = {
      description = "Titan VM";
      after = ["network.target" "libvirtd.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        QEMU_OPTS = lib.concatStringsSep " " [
          "-m ${cfg.memory}"
          "-smp ${toString cfg.cores}"
          "-nographic"
          "-virtfs local,path=${secretsStaging},mount_tag=secrets,security_model=mapped-xattr,readonly=on"
        ];
        QEMU_NET_OPTS = lib.concatStringsSep "," [
          "hostfwd=tcp:127.0.0.1:${toString port}-:18789"
          "hostfwd=tcp:0.0.0.0:${toString sshPort}-:${toString (builtins.head vmConfig.config.services.openssh.ports)}"
          "hostfwd=tcp:127.0.0.1:${toString ttydPort}-:${toString vmConfig.config.port-selector.ports.ttyd}"
        ];
        NIX_DISK_IMAGE = "${cfg.dataDir}/titan.qcow2";
        USE_TMPDIR = "0";
      };

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        WorkingDirectory = cfg.dataDir;

        ExecStartPre = let
          stageScript = pkgs.writeShellScript "stage-titan-vm-secrets" (
            ''
              rm -rf ${secretsStaging}/*
            ''
            + lib.concatStringsSep "\n" (lib.mapAttrsToList
              (name: src: "cp ${src} ${secretsStaging}/${name} && chmod 400 ${secretsStaging}/${name}")
              cfg.secretFiles)
          );
        in "+${stageScript}";

        ExecStart = "${vm}/bin/run-titan-vm";
      };
    };

    myNixOS.services.caddy.serviceMap.openclaw = {
      inherit port;
    };

    myNixOS.services.caddy.serviceMap.ttydtitan = {
      port = ttydPort;
      basic-auth = {
        username = "admin";
        hashed-password = "$2a$14$3elBL1TrHKl9Ei10/PqFfudA8v939SirZN1sAynDbsWOE5t.eT3AK";
      };
    };
  };
}
