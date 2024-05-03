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

  myHomeManager = {
    neovim.enable = true;
    zsh.enable = true;
    ssh.enable = true;
    git.enable = true;
    nix-index.enable = true;
    starship.enable = true;
  };

  home.packages = with pkgs; [
    git
    gnupg
    nushell
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
    nodejs_20
    ruby
    unzip
    cargo
    rustc
    nh
    just
    luajit
    luajitPackages.luarocks
  ];

  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixconf";
  };
  home.sessionPath = [
    "/home/cramt/.local/share/gem/ruby/3.1.0/bin"
  ];
}
