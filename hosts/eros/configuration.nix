{ inputs, lib, pkgs, config, ... }:
let
  steamlink = pkgs.callPackage ../../packages/steamlink {};
in
{
  imports = [
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.display-vc4
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.bluetooth
    inputs.nixos-raspberrypi.nixosModules.sd-image
  ];

  # nixos-raspberrypi modules expect their own flake passed as a module arg
  # (used to pull rpi-specific kernel/firmware packages). Wire it up since
  # we go through our own myLib.mkSystem rather than their lib.nixosSystem.
  _module.args.nixos-raspberrypi = inputs.nixos-raspberrypi;

  nix.settings = {
    trusted-users = [ "cramt" ];

    substituters = [
      "https://nix-community.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  myNixOS = {
    services.sshd.enable = true;
  };

  # Eros is a kiosk — no desktop, no theming.
  stylix.enable = lib.mkForce false;

  # Override the global lix default. Lix's build pulls a full Python test env
  # (aiohttp → flask → ipython) and two ipython tests are timing-based and
  # reliably fail under QEMU aarch64 emulation. CppNix has no such tree and
  # eros is a kiosk Pi, so there's nothing to gain from running lix here.
  nix.package = lib.mkForce pkgs.nix;

  nixpkgs = {
    hostPlatform = "aarch64-linux";
    config = {
      allowUnfree = true;
    };
    # nixos-raspberrypi modules reference `pkgs.raspberrypi-utils` and friends
    # that only exist after their overlays are applied. Pulling them in lets
    # the rpi modules resolve their own deps without forking nixpkgs.
    overlays = [
      inputs.nixos-raspberrypi.overlays.pkgs
      inputs.nixos-raspberrypi.overlays.vendor-pkgs
      inputs.nixos-raspberrypi.overlays.vendor-firmware
      inputs.nixos-raspberrypi.overlays.vendor-kernel
      inputs.nixos-raspberrypi.overlays.kernel-and-firmware
      inputs.nixos-raspberrypi.overlays.bootloader
    ];
  };

  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Use the firmware-loads-kernel-directly path instead of u-boot. nixos-
  # raspberrypi defaults to u-boot which references a nixpkgs attribute
  # (`ubootRaspberryPi_64bit`) that's been split into `ubootRaspberryPi4_64bit`
  # in unstable. The "kernel" bootloader avoids u-boot entirely and is faster.
  boot.loader.raspberry-pi.bootloader = "kernel";

  # config.txt firmware tweaks from the modcommunity Steam Link guide.
  # FKMS (vc4-fkms-v3d) was removed from RPi firmware around 2023 — modern
  # boards only ship KMS (the default in nixos-raspberrypi). The historical
  # FKMS-only requirement was a Buster-era constraint; current Steam Link
  # builds run fine on KMS.
  hardware.raspberry-pi.config.all.options = {
    # Wake the HDMI link even when the TV is off / EDID drops at boot.
    hdmi_force_hotplug = { enable = true; value = 1; };
    # Force HDMI mode (vs DVI) so audio is carried over the cable.
    hdmi_drive = { enable = true; value = 2; };
    # Boost HDMI signal level to survive long / cheap cables.
    config_hdmi_boost = { enable = true; value = 4; };
    # Allow 4K@60 negotiation. Future-proofs the EDID handshake.
    hdmi_enable_4kp60 = { enable = true; value = 1; };
    # Bigger CMA window so the GPU has room for video decode buffers.
    gpu_mem = { enable = true; value = 256; };
  };

  # Steam Link wants /dev/uinput for virtual controller emulation, and xpadneo
  # gives proper Xbox controller (rumble, battery) support over Bluetooth.
  boot.kernelModules = [ "uinput" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.xpadneo ];

  networking = {
    hostName = "eros";
    useNetworkd = true;
  };

  systemd = {
    network = {
      enable = true;

      networks."10-lan" = {
        matchConfig.Name = "end0";
        networkConfig.DHCP = "yes";
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };

  users.users.cramt = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "render" "input" "audio" "plugdev" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com"
    ];
  };

  users.groups.plugdev = {};

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
    neovim
    btop
    cage
    steamlink
  ];

  # Audio: pipewire over HDMI. Steam Link's bundled SDL3 talks to PulseAudio,
  # which pipewire-pulse provides.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = false;
    pulse.enable = true;
  };

  # Steam Link's controller udev rules + uinput module-load fragment ship from
  # the package so changes track upstream.
  services.udev.packages = [ steamlink ];

  # Boot straight into a fullscreen Wayland kiosk running Steam Link via cage.
  # Cage starts XWayland for Qt 5.14's xcb platform plugin (the bundled Qt has
  # no native Wayland plugin). default_session re-runs the kiosk so a crash
  # doesn't strand the TV on a blank tty.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "${pkgs.cage}/bin/cage -s -- ${steamlink}/bin/steamlink";
        user = "cramt";
      };
      default_session = {
        command = "${pkgs.cage}/bin/cage -s -- ${steamlink}/bin/steamlink";
        user = "cramt";
      };
    };
  };

  services.dbus.enable = true;

  hardware.enableRedistributableFirmware = true;

  system.stateVersion = "25.11";
}
