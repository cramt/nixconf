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
  services.scx.enable = true;
  boot.extraModprobeConfig = ''
    options usbhid mousepoll=2
  '';

  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  nix = {
    settings = let
      caches = ["https://cache.nixos.org/" "http://192.168.0.103:5000/" "http://192.168.0.106:5000/"];
    in {
      # this doesnt work when the hosts arent available https://github.com/NixOS/nix/issues/6901
      # should only be using this strategy on the server
      #trusted-substituters = caches;
      #substituters = caches;
      experimental-features = ["nix-command" "flakes"];
      extra-platforms = config.boot.binfmt.emulatedSystems;
    };
  };

  networking.firewall.enable = true;

  myNixOS = {
    waydroid = {
      enable = true;
      armEmulation = "libhoudini"; # Intel CPU - libhoudini works better
      properties = {
        suspend = false; # Keep container running, don't freeze when no UI
        fake_touch = ["com.riotgames.*"]; # Make mouse act as touch for games
      };
      apps.apkpure = [
        "com.microsoft.teams"
        "com.riotgames.legendsofruneterra"
      ];
      desktopEntries = [
        {
          id = "com.microsoft.teams";
          name = "Microsoft Teams";
          comment = "Chat and collaboration";
          categories = ["Network" "Chat" "Office"];
        }
        {
          id = "com.riotgames.legendsofruneterra";
          name = "Legends of Runeterra";
          comment = "Strategy card game";
          categories = ["Game" "CardGame"];
        }
      ];
    };
    gnupg.enable = true;
    qemu.enable = true;
    docker.enable = true;
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/terantula_nebula.jpg;
    bundles.graphical.enable = true;
    steam.enable = true;
    amd.enable = true;
    bundles.users.enable = true;
    services = let
      downloads = {
        raw = "/mnt/amirani/raw_downloads";
        movies = "/mnt/amirani/movies";
        tvshows = "/mnt/amirani/tvshows";
      };
    in {
      titan-vm = {
        enable = false;
      };
      ollama = {
        enable = true;
        gpu = "rocm";
        rocmVersion = "11.0.1";
      };
      nixarr.enable = true;
      jellyfin = {
        enable = false;
        configVolume = "/mnt/amirani/configs/jellyfin";
        mediaVolumes = {
          tvshows = downloads.tvshows;
          movies = downloads.movies;
        };
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
      homelab_system_controller = {
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

  environment.systemPackages = with pkgs; [
    codexbar
  ] ++ (config.environment.systemPackages or []);



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

  boot.kernelParams =
    builtins.map
    (
      {
        port,
        res,
        refresh_rate,
        ...
      }: "video=${port}:${toString res.width}x${toString res.height}@${toString refresh_rate}"
    )
    (import ./monitors.nix);

  system.stateVersion = "25.05"; # Did you read the comment?
}
