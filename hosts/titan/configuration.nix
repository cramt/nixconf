{
  pkgs,
  lib,
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

  networking.hostName = "titan";
  networking.useDHCP = lib.mkDefault true;

  # Mount secrets volume from host via 9p
  fileSystems."/run/openclaw-secrets" = {
    device = "secrets";
    fsType = "9p";
    options = ["trans=virtio" "ro" "msize=104857600"];
  };

  myNixOS = {
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/terantula_nebula.jpg;
    bundles.users.enable = true;

    home-users = {
      "cramt" = {
        userConfig = ./home.nix;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    htop
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "25.11";
}
