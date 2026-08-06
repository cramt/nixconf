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
    (import ./disko.nix {device = "/dev/nvme0n1";})
  ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    kernelPackages = pkgs.linuxKernel.packages.linux_zen;
  };

  security.polkit.enable = true;

  services.desktopManager.plasma6.enable = true;
  programs.kdeconnect.enable = true;

  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
    };
    autoLogin = {
      enable = true;
      user = "cramt";
    };
  };

  myNixOS = {
    nvidia = {
      enable = true;
      # GTX 1050 Ti (GP107M, Pascal). NVIDIA dropped Maxwell/Pascal/Volta after
      # the 580 branch, so `stable` (595.x) builds and deploys fine here and
      # then can't bind the card — a dead TV, not an obvious driver error.
      # Remove this pin only if the card is replaced with Turing or newer.
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    };
    bundles.general.stylixAsset = ../../media/artemis2_1.jpg;
    bundles.general.enable = true;
    bundles.users.enable = true;

    # Couch console (supersedes eros). Plasma below stays as the "switch to
    # desktop" target and as the fallback while autoStart is off.
    console = {
      enable = true;
      # Flip to true once `steam-gamescope` is confirmed to start on this
      # laptop's NVIDIA — see modules/gaming/console.nix for why it isn't
      # on by default.
      autoStart = false;
    };

    services = {
      sshd.enable = true;
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

  # Never sleep, even on lid close
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    IdleAction = "ignore";
  };
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowSuspendThenHibernate = "no";
    AllowHybridSleep = "no";
  };

  networking.hostName = "ganymede";
  networking.networkmanager.enable = true;

  services.xserver = {
    xkb = {
      variant = "nodeadkeys";
      layout = "dk";
    };
  };

  console.keyMap = "dk-latin1";

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
  };

  environment.systemPackages = [
    pkgs.ghostty.terminfo
  ];

  system.stateVersion = "26.05";
}
