{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: let
in {
  boot.extraModulePackages = [];

  boot.initrd.includeDefaultModules = false;

  # Force a minimal set. For SD-boot on Pi 4, you can often go *very* small.
  # Start with just USB input (optional) and SD support.
  boot.initrd.availableKernelModules = lib.mkForce [
    "mmc_block"
    "sd_mod"
    "usbhid"
  ];

  # No encryption/LVM → no need for extra initrd kernel modules
  boot.initrd.kernelModules = lib.mkForce [];
  boot.kernelModules = [
    "vc4"
    "v3d"
  ];

  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
    options = ["nofail"];
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD"; # this is important!
    fsType = "ext4";
    options = ["noatime"];
  };

  swapDevices = [];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.end0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlan0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
