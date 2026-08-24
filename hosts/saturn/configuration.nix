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
  # explicit chainload entry for the League dual-boot on the 970 EVO's part1. Windows'
  # \EFI\Microsoft\Boot lives on this shared ESP (put there by
  # scripts/saturn-windows-image.sh; see docs/saturn-disko-migration.md).
  boot.loader.systemd-boot.extraEntries."windows.conf" = ''
    title   Windows 11
    efi     /EFI/Microsoft/Boot/bootmgfw.efi
  '';
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;

  # Saturn ran swapless, so under memory pressure the only reclaimable thing was
  # page cache — the kernel evicted mapped executables and re-faulted them off
  # disk, freezing the desktop for minutes before the OOM killer finally fired
  # (2026-08-05: Minecraft 12G + claude-code 10G on 32G). zram gives reclaim a
  # cheap destination and lets systemd-oomd's swap trigger work at all.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
  boot.kernel.sysctl = {
    # zram-backed swap is RAM-speed, so swapping beats dropping page cache.
    "vm.swappiness" = 180;
    # Readahead is pure waste when the "disk" is compressed RAM.
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };

  # The MX Vertical talks HID++ through the Unifying receiver, and the kernel's
  # hidpp driver only surfaces a coarse capacity_level ("Normal"); the percentage
  # upower reports is synthesised from that and is tagged "should be ignored".
  # Solaar reads the device directly and gives a usable number — though the mouse
  # only implements HID++ feature 0x1000 (BATTERY STATUS), not 0x1001 (voltage),
  # so even that steps 100/50/20/5 rather than draining smoothly.
  #
  # enable pulls in hardware.logitech.wireless (the udev rules that make the
  # receiver's hidraw node readable without root); userService is the tray icon,
  # which starts hidden and hangs off graphical-session.target.
  programs.solaar = {
    enable = true;
    userService = {
      enable = true;
      # Solaar loses the receiver across suspend/resume and the tray icon goes
      # stale rather than erroring, so it re-scans on wake instead.
      extraArgs = ["--restart-on-wake-up"];
    };
  };

  # Decode + log machine-check exceptions into human-readable form (which DIMM,
  # which error) and track corrected-error counts. Diagnosing CPU/RAM MCEs.
  hardware.rasdaemon.enable = true;
  boot.extraModprobeConfig = ''
    options usbhid mousepoll=2
    options snd-intel-dspcfg dsp_driver=1
  '';

  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  # The @root subvol came up owned by uid 777, which makes systemd-tmpfiles
  # refuse every "unsafe path transition" out of `/` — including the
  # `L+ /run/binfmt/aarch64-linux` rule. That symlink then keeps pointing at
  # whichever qemu store path existed at boot while nix.conf's sandbox-paths
  # follows the current system, so emulated builds die with ENOENT on their
  # interpreter. `/` sorts first, so tmpfiles repairs it in the same pass.
  systemd.tmpfiles.rules = ["z / 0755 root root - -"];

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
    # Keep the cached Windows image from rotting. Rebuild only — deploying to
    # the real partition stays a deliberate `--deploy-only` you run yourself.
    services.windows-image-refresh = {
      enable = true;
      user = "cramt";
    };
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
      # Off: the preauth-key join kept failing, and tailscaled without
      # `authKeyFile` is a daemon that never registers with headscale at all
      # (the module's baseURL is an auth-key parameter, not --login-server).
      # Flip back to true to retry the join.
      tailscale.enable = false;
      # T3 Code server as a user unit, same as luna, so saturn's agents are
      # reachable from a phone/laptop without the desktop app being open. No
      # on-disk SSH key: this host has a session with 1Password's agent.
      #
      # It shares ~/.t3 with the desktop app, which spawns its own backend on
      # launch — nothing upstream locks the data dir (verified: two servers
      # start happily over one), so don't run both at once. Use the web UI at
      # this host's t3code port, or stop the unit before opening the app.
      t3code.enable = true;
      sunshine.enable = true;
      # Off: the RPC worker kept failing. luna's llama-cpp instance used to
      # offload here, so its `rpc` list is empty until this comes back.
      llama-cpp-rpc = {
        enable = false;
        gpu = "rocm";
        rocmVersion = "11.0.1";
        port = 50052;
      };
      # colibrì streams MoE expert weights off the dedicated /llm partitions
      # (hosts/saturn/disko.nix). The CLI ships now because staging the weights
      # NEEDS it — `coli convert`/`download` populate /llm/primary, and
      # `coli doctor`/`plan`/`tune` are how you find out what this box actually
      # does before committing a tuned profile.
      #
      # serve.enable stays false until /llm/primary holds a model: the daemon
      # would otherwise crash-loop against an empty mountpoint. Flip it, set
      # model/mirror, and put whatever `coli tune` measures into
      # serve.environment. See docs/saturn-llm-storage.md.
      colibri = {
        enable = true;
        backend = "rocm";
        serve = {
          enable = true;
          # NOT at boot. The engine needs ~20GB free and a logged-in COSMIC
          # session routinely holds that, in which case it refuses to start
          # rather than be OOM-killed — at boot that is just a failed unit.
          # `systemctl start colibri` when you actually want it.
          autoStart = false;
          # Run as the human, not a system user: `.coli_usage` lives next to the
          # model, so the daemon and an interactive `coli chat` have to be the
          # same identity or they learn separate histories.
          user = "cramt";
          model = "/llm/primary/glm52-i4";
          mirror = "/llm/mirror/glm52-i4";
          # Measured RSS on the first run was 13.7 GB and the planner budgets
          # ~21 GB from *available* RAM, so it self-limits before this bites.
          # This is the backstop that makes an overshoot degrade rather than take
          # the desktop session down with it — 22G leaves ~9 GiB plus zram.
          memoryMax = "22G";
          # Leave the desktop ~6 GB of the 16 GB. Letting the planner size this
          # itself took 13.3 GB and killed Discord outright, which is not a
          # tradeoff worth making on the machine you are sitting at.
          vram = 10;
          # serve.environment stays empty until `coli tune` has actually run on
          # the GPU-detected plan. The current auto-tune hints (DRAFT=0,
          # COLI_CUDA_PIPE=1) come from a plan taken before the rocm-smi fix was
          # deployed, and hardcoding those would be guessing with extra steps.
        };
      };
      nixarr.enable = false;
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
  };

  nixarr = {
    mediaDir = "/var/lib/nixarr-test/media";
    stateDir = "/var/lib/nixarr-test/.state";
  };

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
