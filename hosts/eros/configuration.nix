{
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = with inputs.nixos-raspberrypi.nixosModules; [
    raspberry-pi-4.base
    raspberry-pi-4.display-vc4
    raspberry-pi-4.bluetooth
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.buildPlatform = "x86_64-linux";

  networking.hostName = "eros";

  programs.kdeconnect.enable = true;

  environment.systemPackages = with pkgs; [
    neovim
    wget
    moonlight-embedded
    ghostty
  ];

  myNixOS = {
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/terantula_nebula.jpg;
    bundles.users.enable = true;
    services.sshd.enable = true;
    services.hotspot.enable = true;
  };

  programs.zsh.enable = true;
  users.users.cramt = {
    isNormalUser = true;
    initialPassword = "12345";
    description = "";
    shell = pkgs.zsh;
    extraGroups = [
      "libvirtd"
      "networkmanager"
      "wheel"
      "pipewire"
      "docker"
      "storage"
      "gamemode"
      "plugdev"
      "dailout"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com"
    ];
  };

  networking.networkmanager.enable = true;

  nix.extraOptions = ''
    keep-outputs = true
    keep-derivations = true
    experimental-features = nix-command flakes
  '';

  system.stateVersion = "25.11";
  programs = {
    sway.enable = true;
  };

  services.dbus.enable = true;

  users.users.greeter = {
    isSystemUser = true;
    group = "greeter";
  };
  users.groups.greeter = {};

  services.greetd = {
    enable = true;
    restart = false;

    settings = {
      initial_session = {
        user = "cramt";
        command = "${pkgs.systemd}/bin/systemd-cat -t sway -- env WLR_RENDERER=pixman ${pkgs.sway}/bin/sway -d";
      };

      default_session = {
        user = "greeter";
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd ${pkgs.sway}/bin/sway";
      };
    };
  };
}
