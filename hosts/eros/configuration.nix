{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    inputs.nixos-generators.nixosModules.all-formats
  ];

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  networking.hostName = "eros";

  environment.systemPackages = with pkgs; [
    neovim
    wget
  ];

  myNixOS = {
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/terantula_nebula.jpg;
    bundles.users.enable = true;
    services.sshd.enable = true;
    services.hotspot.enable = true;
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

  networking.networkmanager.enable = true;

  nix.extraOptions = ''
    keep-outputs = true
    keep-derivations = true
    experimental-features = nix-command flakes
  '';

  system.stateVersion = "25.05";
}
