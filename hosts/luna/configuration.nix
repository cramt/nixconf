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
    powertop.enable = true;
    bundles.general.enable = true;
    bundles.users.enable = true;

    services =
      let
        downloads = {
          raw = "/mnt/crisium/downloads/raw";
          movies = "/mnt/crisium/downloads/movies";
          tvshows = "/mnt/imbrium/downloads/tvshows";
        };
      in
      {
        jellyfin = {
          enable = true;
          configVolume = "/mnt/pierre/configs/jellyfin";
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
          enable = true;
          cacheVolume = "/mnt/pierre/configs/caddy-cache";
          staticFileVolumes = {
            files = "/tmp/caddy_static_files";
          };
          domain = "cramt.schniebster.dk";
          protocol = "https";
        };
        qbittorrent = {
          enable = true;
          configVolume = "/mnt/pierre/configs/qbittorrent";
          downloadVolume = downloads.raw;
        };
        foundryvtt = {
          enable = true;
          dataVolume = "/mnt/pierre/configs/foundryvtt_a";
        };
        prowlarr = {
          enable = true;
          configVolume = "/mnt/pierre/configs/prowlarr";
        };
        radarr = {
          enable = true;
          configVolume = "/mnt/pierre/configs/radarr";
          downloadVolume = downloads.raw;
          movieVolume = downloads.movies;
        };
        sonarr = {
          enable = true;
          configVolume = "/mnt/pierre/configs/sonarr";
          downloadVolume = downloads.raw;
          tvVolume = downloads.tvshows;
        };
        bazarr = {
          enable = true;
          configVolume = "/mnt/pierre/configs/bazarr";
          downloadVolume = downloads.raw;
          tvVolume = downloads.tvshows;
          movieVolume = downloads.movies;
        };
        adguard = {
          enable = true;
          configVolume = "/mnt/pierre/configs/adgaurd_conf";
          workVolume = "/mnt/pierre/configs/adgaurd_work";
        };
        homelab_discord_bot = {
          enable = true;
          databaseUrl = "sqlite:/mnt/pierre/homelab_discord_bot.db?mode=rwc";
        };
        sshd.enable = true;
      };

    home-users = {
      "cramt" = {
        userConfig = ./home.nix;
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBiRJVi8CUq/fZIr568Ku4+XQmMDvsqpv/KE7wjJm+hu thathannahfield@gmail.com"
        ];
      };
    };
  };

  networking.hostName = "luna";

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

  # Configure keymap in X11
  services.xserver = {
    xkb = {
      variant = "nodeadkeys";
      layout = "dk";
    };
  };

  # Configure console keymap
  console.keyMap = "dk-latin1";


  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-substituters = [ "192.168.0.106:5000" "https://cache.nixos.org/" ];
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
