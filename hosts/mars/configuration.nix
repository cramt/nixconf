{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  security.polkit.enable = true;

  #boot.kernelPackages = pkgs.linuxPackages_cachyos;
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;
  services.scx.enable = true;
  boot.extraModprobeConfig = ''
    options usbhid mousepoll=2
  '';

  networking.firewall.allowedTCPPorts = [3600];

  myNixOS.secrets.zammadHttpToken = {
    reference = "op://Homelab/Zammad/httpToken";
    mode = "0640";
    group = (import ../../myLib/secrets.nix).group;
  };

  # The M365 work account (email, password, TOTP seed) for the outlook skill's
  # `outlook-browser login`. Same 1Password item luna's Copilot proxy reads.
  myNixOS.secrets.m365Account = {
    reference = "op://Homelab/M365Copilot/secretsJson";
    mode = "0640";
    group = (import ../../myLib/secrets.nix).group;
  };

  myNixOS = {
    gnupg.enable = true;
    onepassword.enable = true;
    t3code-remotes.enable = true;
    docker.enable = true;
    bluetooth.enable = true;
    intel-gpu.enable = true;
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/artemis2_1.jpg;
    bundles.graphical.enable = true;
    niri.enable = true;
    bundles.users.enable = true;
    steam = {
      enable = true;
      frame.enable = true;
    };

    services = {
      sshd.enable = true;
      # T3 Code server, linked with the rest of the fleet (myLib/t3code-fleet.nix).
      # Like saturn: it takes ~/.t3, and the desktop app moves to ~/.t3-desktop
      # and reaches it as a saved connection (t3code-remotes).
      t3code.enable = true;
      caddy = {
        enable = false;
        domain = "localhost";
        staticFileVolumes = {};
        cacheVolume = "/tmp/b";
      };
      servatrice.enable = false;
    };
  };

  networking.networkmanager.enable = true;
  # NetworkManager pulls ModemManager in by default; there is no modem here.
  networking.modemmanager.enable = false;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  services.displayManager.gdm.enable = true;
  services.desktopManager.cosmic.enable = true;

  # Configure keymap in X11
  services.xserver = {
    xkb = {
      variant = "nodeadkeys";
      layout = "dk";
    };
  };

  # Configure console keymap
  console.keyMap = "dk-latin1";

  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  nix.settings = let
    caches = ["https://cache.nixos.org/" "http://192.168.0.103:5000/" "http://192.168.0.107:5000/"];
  in {
    # this doesnt work when the hosts arent available https://github.com/NixOS/nix/issues/6901
    # should only be using this strategy on the server
    #trusted-substituters = caches;
    #substituters = caches;
    experimental-features = ["nix-command" "flakes"];
    extra-platforms = config.boot.binfmt.emulatedSystems;
  };
  environment.systemPackages = [
  ];

  system.stateVersion = "26.05";
}
