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

  boot.kernelPackages = pkgs.linuxPackages_cachyos;
  services.scx.enable = true;

  networking.firewall.allowedTCPPorts = [3600];

  myNixOS = {
    gnupg.enable = true;
    qemu.enable = true;
    docker.enable = true;
    bluetooth.enable = true;
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/terantula_nebula.jpg;
    bundles.graphical.enable = true;
    bundles.users.enable = true;
    steam = {
      enable = true;
    };

    services.tor-privoxy = {
      enable = false;
    };
    services = {
      synapse.enable = false;
      caddy = {
        enable = false;
        domain = "localhost";
        staticFileVolumes = {};
        cacheVolume = "/tmp/b";
      };
      servatrice.enable = false;
      gtnh = {
        enable = false;
        dataVolume = "/home/cramt/gtnh";
      };
      valheim = {
        enable = false;
        worldVolume = "/tmp/a";
        binaryVolume = "/tmp/b";
        serverName = "wutwutgame3";
        worldName = "wutwutgame3";
      };
    };

    home-users = {
      "cramt" = {
        userConfig = ./home.nix;
      };
    };
  };

  networking.hostName = "mars";

  networking.networkmanager.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  services.displayManager.cosmic-greeter.enable = true;
  #services.desktopManager.cosmic.enable = true;

  # Configure keymap in X11
  services.xserver = {
    xkb = {
      variant = "nodeadkeys";
      layout = "dk";
    };
  };

  # Configure console keymap
  console.keyMap = "dk-latin1";

  nix.settings = let
    caches = ["https://cache.nixos.org/" "http://192.168.0.103:5000/" "http://192.168.0.107:5000/"];
  in {
    # this doesnt work when the hosts arent available https://github.com/NixOS/nix/issues/6901
    # should only be using this strategy on the server
    #trusted-substituters = caches;
    #substituters = caches;
    experimental-features = ["nix-command" "flakes"];
  };
  environment.systemPackages = [
  ];

  system.stateVersion = "25.05";
}
