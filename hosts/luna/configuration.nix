{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    inputs.disko.nixosModules.default
    (import ./disko.nix {device = "/dev/disk/by-id/ata-Samsung_SSD_850_EVO_250GB_S2R4NB0J105220R";})
  ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  security.polkit.enable = true;

  # T3 Code checks out git worktrees under ~/.t3, each carrying a multi-GB Rust
  # `target/` (one Windows cross-compile target alone hit 67G) — that filled
  # luna's 228G root. Relocate the bytes to /pool (5.3T) with a bind mount, NOT
  # a symlink: Claude Code keys its session transcripts (~/.claude/projects/<enc>)
  # by the *realpath* of the agent's cwd, and a symlink would resolve ~/.t3 →
  # /pool, changing that key and orphaning every existing agent's history. A bind
  # mount is transparent to realpath, so ~/.t3 stays canonical while the data
  # lives on /pool/t3code.
  fileSystems."/home/cramt/.t3" = {
    device = "/pool/t3code";
    fsType = "none";
    options = ["bind"];
    depends = ["/pool"];
  };

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;

  programs.hyprland = {
    enable = false;
    withUWSM = false;
  };

  myNixOS = {
    opnix-secrets.enable = true;
    services.m365-copilot-proxy.enable = true;
    gnupg.enable = true;
    nvidia.enable = true;
    docker = {
      enable = true;
      httpPort = 2375;
    };
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/artemis2_1.jpg;
    bundles.users.enable = true;

    services = {
      # T3 Code server: offload coding-agent work to luna from the mars/saturn
      # desktop app. Runs as cramt so agents get git/ssh + the agent CLIs
      # (dev bundle). Reachable on the LAN and at t3.<domain> behind authelia;
      # either way, pair a client with `just t3_pair`.
      t3code = {
        enable = true;
        user = "cramt";
        subdomain = "t3";
        # Headless: no 1Password agent here, so agents need the key on disk.
        onDiskSshKey.enable = true;
        # opencode ships disabled in t3code (opt-in from its settings UI). The
        # binary it finds on the unit's PATH is the dev bundle's wrapper, which
        # points it at the work pool — see modules/hm-features/opencode.nix.
        providers.opencode = true;
      };
      # Always-on target for claude.ai/code and the phone app; uses the direct
      # claude.ai login in ~/.claude.json (luna is off the account pool).
      claude-remote-control.enable = true;
      nixarr.enable = true;
      # Passkey portal for the owner-only vhosts (caddy serviceMap forward-auth).
      authelia = {
        enable = true;
        # Plaintext lives in op://Homelab/Authelia/password; only needed to
        # enroll a passkey on a new device.
        user.hashedPassword = "$argon2id$v=19$m=65536,t=3,p=4$fT170oQb3iDhmNYoqCpTZA$80k++XmJ8d5NRibh16c7CZXOwTHnemn3IZDIoFj2SS0";
      };
      recyclarr.enable = true;
      cleanuparr = {
        enable = true;
        dataVolume = "/pool/configs/cleanuparr";
      };
      # Fleet metrics land here: luna is the always-on host and the only one
      # running caddy, which is what the roaming agents push through.
      metrics.server = {
        enable = true;
        # 200GB of TSDB has no business on the 228G root SSD, and /pool is
        # where every other data-heavy service on this box already lives.
        dataDir = "/pool/prometheus";
        dataDirDepends = ["/pool"];
        # bcrypt from `caddy hash-password`; the plaintext lives in
        # op://Homelab/Metrics/remoteWritePassword and reaches agents via opnix.
        auth.hashedPassword = "$2a$14$np6mAmdVPkGBrPrFnV4rSeUw45WaHHvVngHupMyOSyClwwnL7444a";
      };
      garage.enable = false;
      btopttyd.enable = false;
      minecraft-forge = {
        enable = false;
        url = "https://www.curseforge.com/minecraft/modpacks/nomi-ceu";
        dataDir = "/pool/minecraft-forge";
      };
      caddy = {
        enable = true;
        cacheVolume = "/pool/configs/caddy-cache";
        staticFileVolumes = {};
        # The cli-proxy-api pool runs as cramt's user unit (development bundle,
        # modules/hm-features/cli-proxy-api.nix). Its web panel still asks for
        # the management key (`agent-accounts key`) behind the passkey.
        serviceMap.cliproxy = {
          inherit (config.home-manager.users.cramt.myHomeManager.cli-proxy-api) port;
          forward-auth = true;
        };
      };
      foundryvtt = {
        enable = true;
        dataVolume = "/pool/configs/foundryvtt_a";
      };
      homelab_system_controller = {
        enable = false;
        databaseUrl = "sqlite:/pool/homelab_discord_bot.db?mode=rwc";
      };
      open-webui.enable = false;
      postgres = {
        dataDir = "/pool/pgsql";
      };
      terraform_remote_backend.enable = true;
      servatrice.enable = true;
      sshd.enable = true;
    };
  };

  networking.networkmanager.enable = true;

  networking.interfaces.enp3s0.wakeOnLan = {
    policy = ["magic"];
    enable = true;
  };

  programs.nix-ld.enable = true;

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
    caches = ["https://cache.nixos.org/" "http://192.168.0.107:5000/" "http://192.168.0.106:5000/"];
  in {
    # this doesnt work when the hosts arent available https://github.com/NixOS/nix/issues/6901
    # should only be using this strategy on the server
    # trusted-substituters = caches;
    # substituters = caches;
    experimental-features = ["nix-command" "flakes"];
  };
  environment.systemPackages = [
    pkgs.ghostty.terminfo
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # The btrfs migration left /pool, /pool/media/.state and .state/nixarr owned
  # by cramt while the service directories beneath them are root- or
  # service-owned. systemd-tmpfiles refuses to descend such a transition and
  # skips the rule while still exiting 0, so every nixarr rule under those
  # paths was silently ignored. Services predating the migration kept working
  # only because their directories already existed. nixarr documents this: a
  # stateDir whose parents are not root-owned is unsupported.
  #
  # `z` rather than `Z` -- adjust these three directories alone, never
  # recursing through the ~4TB of media beneath them.
  systemd.tmpfiles.rules = [
    "z /pool 0755 root root - -"
    "z /pool/media/.state 0755 root root - -"
    "z /pool/media/.state/nixarr 0755 root root - -"
  ];

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
  system.stateVersion = "26.05"; # Did you read the comment?
}
