{ inputs, config, pkgs, lib, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      inputs.disko.nixosModules.default
    ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  security.polkit.enable = true;

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;

  myNixOS = {
    gnupg.enable = true;
    qemu.enable = true;
    bundles.general.enable = true;
    steam.enable = true;
    amd.enable = true;
    bundles.users.enable = true;

    services.jellyfin = {
      enable = true;
      configVolume = "/tmp/jellyfin_config";
      mediaVolumes = {
        tvshows = "/tmp/jellyfin_tvshows";
      };
      gpuDevices = [
        "/dev/dri/card1"
        "/dev/dri/renderD128"
      ];
    };
    services.caddy = {
      enable = true;
      cacheVolume = "/tmp/caddy_cache";
      staticFileVolume = "/tmp/caddy_static_files";
      domain = "localhost";
      protocol = "http";
    };
    services.qbittorrent = {
      enable = true;
      configVolume = "/tmp/qbit_config";
      downloadVolume = "/tmp/qbit_download";
    };
    services.foundryvtt = {
      enable = true;
      dataVolume = "/tmp/foundryvtt_data";
    };

    home-users = {
      "cramt" = {
        userConfig = ./home.nix;
        userSettings = {
          extraGroups = [
            "networkmanager"
            "wheel"
            "libvirtd"
            "docker"
            "adbusers"
            "openrazer"
            "audio"
          ];
        };
      };
    };
  };

  networking.hostName = "io";

  networking.networkmanager.enable = true;

  programs.nix-ld.enable = true;

  nixpkgs = {
    overlays = [
      inputs.nur.overlay
      inputs.neorg-overlay.overlays.default
    ];
    config = {
      allowUnfree = true;
    };
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver = {
    layout = "dk";
    xkbVariant = "nodeadkeys";
  };

  # Configure console keymap
  console.keyMap = "dk-latin1";


  nix.settings.experimental-features = [ "nix-command" "flakes" ];
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
  system.stateVersion = "23.05"; # Did you read the comment?

}
