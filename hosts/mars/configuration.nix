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

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;

  networking.firewall.allowedTCPPorts = [3600];

  myNixOS = {
    gnupg.enable = true;
    qemu.enable = true;
    docker.enable = true;
    bluetooth.enable = true;
    bundles.general.enable = true;
    bundles.general.stylixAssetVideo = ../../media/cosmere.mp4;
    bundles.graphical.enable = true;
    bundles.users.enable = true;

    services.tor-privoxy = {
      enable = false;
    };
    services = {
      synapse.enable = true;
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

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
