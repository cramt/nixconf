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

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;

  programs.hyprland = {
    enable = false;
    withUWSM = false;
  };

  myNixOS = {
    greetd.enable = true;
    opnix-secrets.enable = true;
    services.m365-copilot-proxy.enable = true;
    gnupg.enable = true;
    powertop.enable = true;
    nvidia.enable = true;
    docker = {
      enable = true;
      httpPort = 2375;
    };
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/artemis2_1.jpg;
    bundles.users.enable = true;

    services = {
      claude-remote-control.enable = true;
      nixarr.enable = true;
      tor.enable = true;
      garage.enable = false;
      btopttyd.enable = true;
      minecraft-forge = {
        enable = false;
        url = "https://www.curseforge.com/minecraft/modpacks/nomi-ceu";
        dataDir = "/pool/minecraft-forge";
      };
      minecraft-homestead = {
        enable = true;
        dataDir = "/pool/minecraft-homestead";
      };
      gtnh = {
        enable = true;
        dataVolume = "/pool/gtnh";
      };
      caddy = {
        enable = true;
        cacheVolume = "/pool/configs/caddy-cache";
        staticFileVolumes = {
          books = "/pool/books";
        };
      };
      foundryvtt = {
        enable = true;
        dataVolume = "/pool/configs/foundryvtt_a";
      };
      satisfactory = {
        enable = true;
        maxPlayers = 8;
        beta = true;
        dataVolume = "/pool/satisfactory";
      };
      valheim = {
        enable = true;
        worldVolume = "/pool/valheim_config";
        binaryVolume = "/pool/valheim_binary";
        serverName = "wutwutgame3";
        worldName = "wutwutgame3";
      };
      homelab_system_controller = {
        enable = false;
        databaseUrl = "sqlite:/pool/homelab_discord_bot.db?mode=rwc";
      };
      open-webui.enable = false;
      postgres = {
        dataDir = "/pool/pgsql";
      };
      continuwuity.enable = true;
      terraform_remote_backend.enable = true;
      servatrice.enable = true;
      llama-cpp = {
        enable = true;
        models = [
          {
            name = "qwen3-14b";
            repo = "unsloth/Qwen3-14B-GGUF";
            file = "Qwen3-14B-Q4_K_M.gguf";
            args = ["-ngl" "999" "-c" "16384" "--flash-attn" "on"];
          }
        ];
        instances = {
          default = {
            gpu = "cuda";
            port = 11434;
            rpc = ["192.168.178.23:50052"]; # saturn
          };
        };
      };
      sshd.enable = true;
      harmonia = {
        prio = 50;
        enable = true;
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

  networking.hostName = "luna";

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

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

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
