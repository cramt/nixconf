{
  pkgs,
  lib,
  config,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  virtualisation.vmVariant = {
    virtualisation = {
      graphics = false;
      qemu.options = [
        "-cpu host"
        "-enable-kvm"
      ];
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = ["ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "virtio_blk" "9p" "9pnet_virtio"];
  boot.kernelModules = ["kvm-intel" "9p" "9pnet_virtio"];

  # Register nix store paths from the host's shared 9p store into the VM's nix DB.
  # This must run before home-manager can activate.
  systemd.services.nix-store-register = {
    description = "Register shared nix store paths in local DB";
    wantedBy = ["multi-user.target"];
    before = ["home-manager-cramt.service"];
    after = ["nix-daemon.socket" "nix-.ro\\x2dstore.mount" "nix-store.mount"];
    requires = ["nix-daemon.socket"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
        ${config.nix.package.out}/bin/nix-store --store local --load-db < "''${BASH_REMATCH[1]}"
      fi
    '';
  };

  systemd.services.home-manager-cramt = {
    after = ["nix-store-register.service"];
    requires = ["nix-store-register.service"];
  };

  networking.hostName = "titan";
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.enable = false;

  # Mount secrets volume from host via 9p
  fileSystems."/run/openclaw-secrets" = {
    device = "secrets";
    fsType = "9p";
    options = ["trans=virtio" "ro" "msize=104857600"];
  };

  myNixOS = {
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/artemis2_2.jpg;
    bundles.users.enable = true;
    services.sshd.enable = true;

    home-users = {
      "cramt" = {
        userConfig = ./home.nix;
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com"
        ];
      };
    };
  };

  port-selector.auto-assign = ["ttyd"];

  services.ttyd = {
    enable = true;
    writeable = true;
    port = config.port-selector.ports.ttyd;
    entrypoint = ["${pkgs.shadow}/bin/login" "-f" "cramt"];
    clientOptions = {
      fontFamily = "Iosevka";
      fontSize = "16";
    };
  };

  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    htop
    git
    ghostty.terminfo
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "25.11";
}
