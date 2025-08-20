{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    inputs.nixos-generators.nixosModules.all-formats
  ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  # networking config. important for ssh!
  networking = {
    hostName = "pi";
    interfaces.end0 = {
      ipv4.addresses = [
        {
          address = "192.168.1.42";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.1.1"; # or whichever IP your router is
      interface = "end0";
    };
    nameservers = [
      "192.168.1.1" # or whichever DNS server you want to use
    ];
  };

  # the user account on the machine
  users.users.admin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    initialPassword = "12345";
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # I use neovim as my text editor, replace with whatever you like
  environment.systemPackages = with pkgs; [
    neovim
    wget
  ];

  myNixOS = {
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/terantula_nebula.jpg;
    services.sshd.enable = true;
  };

  nix.extraOptions = ''
    keep-outputs = true
    keep-derivations = true
    experimental-features = nix-command flakes
  '';

  # this allows you to run `nixos-rebuild --target-host admin@this-machine` from
  # a different host. not used in this tutorial, but handy later.
  nix.settings.trusted-users = ["admin"];

  # ergonomics, just in case I need to ssh into
  programs.zsh.enable = true;
  environment.variables = {
    SHELL = "zsh";
    EDITOR = "neovim";
  };
}
