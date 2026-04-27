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
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  boot = {
    loader.systemd-boot.enable = lib.mkForce false;
    loader.efi.canTouchEfiVariables = true;
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
  };

  security.polkit.enable = true;

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;
  environment.systemPackages = [
    pkgs.sbctl
  ];
  services.scx.enable = true;
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
    opnix-secrets.enable = true;
    gnupg.enable = true;
    onepassword.enable = true;
    qemu.enable = true;
    docker.enable = true;
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/artemis2_2.jpg;
    bundles.graphical.enable = true;
    steam.enable = true;
    amd.enable = true;
    bundles.users.enable = true;
    services = {
      sunshine.enable = true;
      llama-cpp = {
        enable = true;
        models = [
          # --- Option 1: Qwen3.6-27B (smartest, tight VRAM fit) ---
          # ~13GB model + quantized KV cache. Fits 16GB with headroom.
          # If this crashes your desktop again, switch to option 2 or 3.
          # {
          #  name = "qwen3.6-27b";
          #  repo = "unsloth/Qwen3.6-27B-GGUF";
          #  file = "Qwen3.6-27B-UD-Q3_K_XL.gguf";
          #  args = ["-ngl" "999" "-c" "8192" "--flash-attn" "on" "-ctk" "iq4_nl" "-ctv" "iq4_nl"];
          # }
          # --- Option 2: Qwen3-14B (balanced, comfortable fit) ---
          # ~9GB model. Plenty of VRAM headroom, bigger context possible.
          {
            name = "qwen3-14b";
            repo = "unsloth/Qwen3-14B-GGUF";
            file = "Qwen3-14B-Q4_K_M.gguf";
            args = ["-ngl" "999" "-c" "16384" "--flash-attn" "on"];
          }
          # --- Option 3: Qwen3.5-9B (fastest, safest, most headroom) ---
          # ~6GB model. Tons of room, can push context way up.
          # {
          #   name = "qwen3.5-9b";
          #   repo = "unsloth/Qwen3.5-9B-GGUF";
          #   file = "Qwen3.5-9B-UD-Q4_K_XL.gguf";
          #   args = ["-ngl" "999" "-c" "32768" "--flash-attn" "on"];
          # }
        ];
        instances = {
          default = {
            gpu = "rocm";
            rocmVersion = "11.0.1";
            port = 11434;
          };
        };
      };
      yelliv = {
        enable = true;
        discord = {
          enable = true;
          guildId = "337731942399082498";
          userId = "149996010314137600";
        };
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

  system.stateVersion = "25.11"; # Did you read the comment?
}
