{ inputs, config, pkgs, lib, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
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
    bundles.graphical.enable = true;
    steam.enable = true;
    amd.enable = true;
    bundles.users.enable = true;
    services =
      let
        downloads = {
          raw = "/mnt/amirani/raw_downloads";
          movies = "/mnt/amirani/movies";
          tvshows = "/mnt/amirani/tvshows";
        };
      in
      {
        jellyfin = {
          enable = true;
          configVolume = "/mnt/amirani/configs/jellyfin";
          mediaVolumes = {
            tvshows = downloads.tvshows;
            movies = downloads.movies;
          };
          externalPort = true;
          gpuDevices = [
            "/dev/dri/card1"
            "/dev/dri/renderD128"
          ];
        };
        caddy = {
          enable = false;
          cacheVolume = "/mnt/amirani/configs/caddy-cache";
          staticFileVolumes = { };
          domain = "localhost";
          protocol = "http";
        };
        qbittorrent = {
          enable = false;
          configVolume = "/mnt/amirani/configs/qbittorrent";
          downloadVolume = downloads.raw;
        };
        foundryvtt = {
          enable = false;
          dataVolume = "/mnt/amirani/configs/foundryvtt_a";
        };
        prowlarr = {
          enable = false;
          configVolume = "/mnt/amirani/configs/prowlarr";
        };
        radarr = {
          enable = false;
          configVolume = "/mnt/amirani/configs/radarr";
          downloadVolume = downloads.raw;
          movieVolume = downloads.movies;
        };
        sonarr = {
          enable = false;
          configVolume = "/mnt/amirani/configs/sonarr";
          downloadVolume = downloads.raw;
          tvVolume = downloads.tvshows;
        };
        bazarr = {
          enable = false;
          configVolume = "/mnt/amirani/configs/bazarr";
          downloadVolume = downloads.raw;
          tvVolume = downloads.tvshows;
          movieVolume = downloads.movies;
        };
        adguard = {
          enable = false;
          configVolume = "/mnt/amirani/configs/adgaurd_conf";
          workVolume = "/mnt/amirani/configs/adgaurd_work";
        };
        homelab_discord_bot = {
          enable = false;
          databaseUrl = "sqlite:/mnt/amirani/homelab_discord_bot.db?mode=rwc";
        };
      };

    home-users = {
      "cramt" = {
        userConfig = ./home.nix;
      };
    };
  };

  networking.hostName = "saturn";

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
    xkb = {
      variant = "nodeadkeys";
      layout = "dk";
    };
  };

  # Configure console keymap
  console.keyMap = "dk-latin1";


  nix.settings =
    let
      caches = [ "https://cache.nixos.org/" "http://192.168.0.103:5000/" "http://192.168.0.106:5000/" ];
    in
    {
      # this doesnt work when the hosts arent available https://github.com/NixOS/nix/issues/6901
      # should only be using this strategy on the server
      #trusted-substituters = caches;
      #substituters = caches;
      experimental-features = [ "nix-command" "flakes" ];
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
