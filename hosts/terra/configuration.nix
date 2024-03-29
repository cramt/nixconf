# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      inputs.disko.nixosModules.default
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  myNixOS = {
    bundles.general.enable = true;
    bundles.users.enable = true;

    sharedSettings.hyprland.enable = true;

    home-users = {
      "cramt" = {
        userConfig = ./home.nix;
        userSettings = {
          extraGroups = ["networkmanager" "wheel" "libvirtd" "docker" "adbusers" "openrazer"];
        };
      };
    };
  };

  networking.hostName = "nixos"; # Define your hostname.

  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver = {
    layout = "dk";
    xkbVariant = "nodeadkeys";
  };

  # Configure console keymap
  console.keyMap = "dk-latin1";


  nix.settings.experimental-features = [ "nix-command" "flakes" ];
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
  system.stateVersion = "23.05"; # Did you read the comment?

}
