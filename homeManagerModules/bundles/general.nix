{
  pkgs,
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.nix-colors.homeManagerModules.default
  ];

  nixpkgs = {
    config = {
      allowUnfree = true;
      experimental-features = "nix-command flakes";
    };
  };

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    firefox
    (nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })
    git
    neovim
    lunarvim
    nushell
    alacritty
    kitty
    zellij
    discord
    htop
    eza
    zoxide
    bat
    ripgrep
    neofetch
    lazygit
    wget
    clang
    nodejs_21
    ruby
    unzip
    llvmPackages.bintools
    rustup
  ];

  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixconf";
  };
}
