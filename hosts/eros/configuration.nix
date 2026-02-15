{ lib, pkgs, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];

  nix.settings = {
    trusted-users = [ "cramt" ];

    substituters = [
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  myNixOS = {
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/terantula_nebula.jpg;
    services.sshd.enable = true;
  };


  nixpkgs = {
    hostPlatform = "aarch64-linux";
    config = {
      allowUnfree = true;
    };
  };

  boot.supportedFilesystems.zfs = lib.mkForce false;
  sdImage.compressImage = false;

  networking = {
    hostName = "eros";
    useNetworkd = true;
  };

  systemd = {
    network = {
      enable = true;

      networks."10-lan" = {
        matchConfig.Name = "end0";
        networkConfig.DHCP = "yes";
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };

  users.users.cramt = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
    neovim
    btop
    sway
  ];


    programs.sway.enable = true;

    services.greetd = {
      enable = true;

      # Autologin straight into Sway
      settings = {
        initial_session = {
          command = "sway";
          user = "cramt";
        };
        # Optional: fallback if initial_session exits (e.g., you log out of Sway)
        # default_session = {
        #   command = "sway";
        #   user = "yourUserName";
        # };
      };
    };

    # For better GPU/DRM for Wayland on the Pi (names may vary by NixOS release)
    hardware.graphics.enable = true; # on older releases: hardware.opengl.enable = true;

    # Often helpful on small ARM SBCs
    services.dbus.enable = true;

    # Logind is enough for Sway; seatd is NOT required if using logind.
    # If you prefer seatd instead, you can do:
    # services.seatd.enable = true;
    # users.users.yourUserName.extraGroups = [ "seat" "video" "input" "render" ];

  hardware.enableRedistributableFirmware = true;

  system.stateVersion = "25.11";
}
