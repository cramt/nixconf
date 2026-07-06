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
    # Declarative partitioning: two-SSD btrfs pool (see disko.nix).
    inputs.disko.nixosModules.default
    ./disko.nix
  ];

  # /nix rides on the same btrfs pool as /, but keep it mounted in stage-1 so the
  # store is available before switch-root (matches the pre-disko behaviour).
  fileSystems."/nix".neededForBoot = true;

  security.polkit.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # memtest86+ entry in the boot menu (run it to chase the Bank-0 memory MCEs;
  # see docs/saturn-mce-bios.md). No USB stick needed.
  boot.loader.systemd-boot.memtest86.enable = true;
  # systemd-boot doesn't reliably auto-detect the Windows Boot Manager, so add an
  # explicit chainload entry for the League dual-boot on nvme1n1p1. Windows'
  # \EFI\Microsoft\Boot lives on this shared ESP (put there by
  # scripts/saturn-windows-image.sh; see docs/saturn-disko-migration.md).
  boot.loader.systemd-boot.extraEntries."windows.conf" = ''
    title   Windows 11
    efi     /EFI/Microsoft/Boot/bootmgfw.efi
  '';
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;

  # Decode + log machine-check exceptions into human-readable form (which DIMM,
  # which error) and track corrected-error counts. Diagnosing CPU/RAM MCEs.
  hardware.rasdaemon.enable = true;
  services.scx.enable = true;
  services.scx.scheduler = "scx_lavd";
  boot.extraModprobeConfig = ''
    options usbhid mousepoll=2
    options snd-intel-dspcfg dsp_driver=1
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
    secureboot.enable = false;
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
    niri.enable = true;
    opnix-secrets.enable = true;
    services.m365-copilot-proxy.enable = true;
    gnupg.enable = true;
    onepassword.enable = true;
    qemu.enable = true;
    docker.enable = true;
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/artemis2_1.jpg;
    bundles.graphical.enable = true;
    steam.enable = true;
    amd.enable = true;
    bundles.users.enable = true;
    services = {
      sshd.enable = true;
      claude-remote-control.enable = true;
      sunshine.enable = true;
      llama-cpp-rpc = {
        enable = true;
        gpu = "rocm";
        rocmVersion = "11.0.1";
        port = 50052;
      };
      nixarr.enable = true;
      caddy = {
        enable = false;
        cacheVolume = "/mnt/amirani/configs/caddy-cache";
        staticFileVolumes = {};
        domain = "localhost";
      };
      foundryvtt = {
        enable = false;
        dataVolume = "/mnt/amirani/configs/foundryvtt_a";
      };
      homelab_system_controller = {
        enable = false;
        databaseUrl = "sqlite:/mnt/amirani/homelab_discord_bot.db?mode=rwc";
      };
    };

    home-users = {
      "cramt" = {
        userConfig = ./home.nix;
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com"
        ];
      };
    };
  };

  nixarr = {
    mediaDir = "/var/lib/nixarr-test/media";
    stateDir = "/var/lib/nixarr-test/.state";
  };

  networking.hostName = "saturn";

  networking.networkmanager.enable = true;

  programs.nix-ld.enable = true;

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

  system.stateVersion = "26.05"; # Did you read the comment?
}
