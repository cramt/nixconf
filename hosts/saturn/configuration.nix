{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  dfnstrate = inputs.defenestrate.packages.${pkgs.stdenv.hostPlatform.system}.dfnstrate;
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Declarative partitioning: Linux on the 980, Windows owns the 970 EVO (see disko.nix).
    inputs.disko.nixosModules.default
    ./disko.nix
    ./sunshine.nix
    ./tv-controller.nix
  ];

  # /nix rides on the same btrfs filesystem as /, but keep it mounted in stage-1 so the
  # store is available before switch-root (matches the pre-disko behaviour).
  fileSystems."/nix".neededForBoot = true;

  security.polkit.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # memtest86+ entry in the boot menu (run it to chase the Bank-0 memory MCEs;
  # see docs/saturn-mce-bios.md). No USB stick needed.
  boot.loader.systemd-boot.memtest86.enable = true;
  # Windows has the 970 EVO to itself, ESP included, and systemd-boot can only
  # load from its own ESP, so there's no menu entry for it. `dfnstrate reboot`
  # points the firmware's one-shot BootNext at the Windows Boot Manager entry
  # whose ESP exists; the rest of the CLI (flash, update, doctor) is what
  # maintains that install.
  environment.systemPackages = [dfnstrate];
  # flash, update and reboot re-exec themselves under sudo (raw disk, BLKPG,
  # efivars: no group grants those), so `.#windows.saturn.build.install` and
  # `dfnstrate reboot` would ask for a password. They re-exec the unwrapped
  # binary (current_exe, behind makeWrapper), so that's the path sudo sees.
  # The flash still makes you type ERASE. build.install uses this same
  # dfnstrate, so after a defenestrate bump it's passwordless again once saturn
  # is switched.
  security.sudo.extraRules = [
    {
      users = ["cramt"];
      commands = [
        {
          command = "${dfnstrate.unwrapped}/bin/dfnstrate";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];
  # Stock (vanilla mainline) kernel, not zen or another patch set: zen's patches
  # panicked every boot on 7.3.4-zen1 (a duplicated worker->task deref in
  # workqueue.c, https://github.com/zen-kernel/zen-kernel/issues/425) and took
  # down every zen host at once. Vanilla is what upstream and Hydra test, and
  # zen bought nothing we ever measured. _latest rather than the LTS default so
  # the fleet stays on one kernel line (ganymede needs >= 7.3 for its hid driver).
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Mounts the Windows SSD. Read-write works because defenestrate turns off Fast
  # Startup, which would otherwise leave NTFS marked in use.
  boot.supportedFilesystems.ntfs = true;

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
    niri.enable = true;
    t3code-remotes.enable = true;
    # Tunnel is declared but stays down until `systemctl start wg-quick-vxn`.
    vpn.vxn.enable = true;
    gnupg.enable = true;
    onepassword.enable = true;
    qemu.enable = true;
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/artemis2_1.jpg;
    bundles.graphical.enable = true;
    steam = {
      enable = true;
      frame.enable = true;
    };
    # ganymede's Moonlight streams games from here. Only up while a graphical
    # session is; autologin and suspend-for-WoL are still undecided.
    # Its apps and stream display mode: ./sunshine.nix.
    sunshine = {
      enable = true;
      user = "cramt";
      wakeOnLan.macAddress = (import ./lan.nix).macAddress;
    };
    amd.enable = true;
    bundles.users.enable = true;
    services = {
      sshd.enable = true;
      # T3 Code server as a user unit, same as luna, so saturn's agents are
      # reachable from a phone/laptop without the desktop app being open. No
      # on-disk SSH key: this host has a session with 1Password's agent.
      #
      # The server locks ~/.t3, so the desktop app runs out of ~/.t3-desktop
      # and reaches this server as a saved connection (t3code-remotes), which
      # is what the shared secret is for.
      t3code.enable = true;
      # Upstream's unit is WantedBy=multi-user.target, so it's up from boot.
      vintagestory = {
        enable = true;
        dataDir = "/srv/vintagestory";
        admins = ["cramt"];
        whitelist = ["Maladorra"];
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

  # The T3 Code server's own settings (myNixOS.services.t3code is the fleet
  # wiring: port, secrets).
  services.t3code = {
    # codex ships enabled in t3code, but there's no codex CLI to run.
    providers.codex = false;
    # Device panel + agent access, tools from the store. No Android SDK
    # here, so its sources are remote ones: SSH device hosts, EAS, Simlock.
    devices = {
      enable = true;
      simlock.enable = true;
    };
  };
  # NetworkManager pulls ModemManager in by default; there is no modem here.
  networking.modemmanager.enable = false;

  programs.nix-ld.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  services.displayManager.gdm.enable = true;
  # Straight into the desktop on the boot after a Claude Code handoff, so
  # the resumed session's terminal shows with nobody at the keyboard.
  myNixOS.handoffAutologin.user = "cramt";
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
