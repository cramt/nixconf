{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    # VM-specific profile for QEMU guest
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # VM configuration - generates run-titan-vm script
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      graphics = false;
      # Port forwards are configured by the host via QEMU_NET_OPTS
      qemu.options = [
        "-cpu host"
        "-enable-kvm"
      ];
    };
  };

  # Boot configuration for VM
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = ["ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "virtio_blk"];
  boot.kernelModules = ["kvm-intel"];

  networking.hostName = "titan";
  networking.useDHCP = lib.mkDefault true;

  # Minimal packages for LLM agent work
  environment.systemPackages = with pkgs; [
    neovim
    git
    curl
    wget
    htop
    tmux
  ];

  myNixOS = {
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/terantula_nebula.jpg;
    bundles.users.enable = true;

    services = {
    };

    home-users = {
      "cramt" = {
        userConfig = ./home.nix;
        authorizedKeys = [
          # Luna's host key for passwordless SSH from luna
          (import ../../hosts/luna/ssh.pub.nix)
          # User keys
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com"
        ];
      };
    };
  };

  # SSH configuration (localhost only access from luna)
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  # Simple password for the VM (only accessible from localhost on luna anyway)
  users.users.cramt = {
    initialPassword = lib.mkForce "titan";
  };

  # Xfce desktop environment for VNC access
  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
    xkb = {
      variant = "nodeadkeys";
      layout = "dk";
    };
  };

  services.displayManager = {
    defaultSession = "xfce";
  };

  console.keyMap = "dk-latin1";

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  system.stateVersion = "25.11";
}
