{ pkgs
, config
, inputs
, ...
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
    git
    gnupg
    lunarvim
    nushell
    alacritty
    kitty
    zellij
    vesktop
    htop
    eza
    zoxide
    bat
    gnumake
    (hiPrio gcc)
    clang
    ripgrep
    neofetch
    lazygit
    wget
    nodejs_21
    ruby
    unzip
    cargo
    rustc
    nh
    brightnessctl
    nwg-launchers
    adwaita-qt
  ];

  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixconf";
  };
  home.sessionPath = [
    "/home/cramt/.local/share/gem/ruby/3.1.0/bin"
  ];
}
