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
    nvidia.enable = true;
    bundles.general.stylixAsset = ../../media/terantula_nebula.jpg;
    bundles.general.enable = true;
    bundles.users.enable = true;

    services = {
      sshd.enable = true;
      ollama = {
        enable = true;
        instances = {
          default = {gpu = "cuda";};
        };
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

  # Never sleep, even on lid close
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    IdleAction = "ignore";
  };
  systemd.sleep.extraConfig = "AllowSuspend=no\nAllowHibernation=no\nAllowSuspendThenHibernate=no\nAllowHybridSleep=no";

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

  system.stateVersion = "25.11";
}
