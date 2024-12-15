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
    bundles.general.stylixAssetVideo = ../../media/cosmere.mp4;
    bundles.graphical.enable = true;
    steam = {
      enable = true;
      swayGamingPackage = (import ./sway_gaming.nix) {
        inherit pkgs;
      };
    };
    amd.enable = true;
    bundles.users.enable = true;
    services = let
      downloads = {
        raw = "/mnt/amirani/raw_downloads";
        movies = "/mnt/amirani/movies";
        tvshows = "/mnt/amirani/tvshows";
      };
    in {
      jellyfin = {
        enable = false;
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
        staticFileVolumes = {};
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

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  #services.xserver.desktopManager.gnome.enable = true;
  services.displayManager.ly = {
    enable = false;
    #settings = {
    #animation = "matrix";
    #bigclock = "fa";
    #hide_borders = true;
    #};
  };

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
    caches = ["https://cache.nixos.org/" "http://192.168.0.103:5000/" "http://192.168.0.106:5000/"];
  in {
    # this doesnt work when the hosts arent available https://github.com/NixOS/nix/issues/6901
    # should only be using this strategy on the server
    #trusted-substituters = caches;
    #substituters = caches;
    experimental-features = ["nix-command" "flakes"];
  };

  boot.kernelParams =
    lib.attrsets.mapAttrsToList
    (
      name: value: "video=${name}:${toString value.res.width}x${toString value.res.height}@${value.refresh_rate}"
    )
    (import ./monitors.nix);

  system.stateVersion = "24.05"; # Did you read the comment?
}
