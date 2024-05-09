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
    java.enable = true;
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
    (inputs.nixpkgs-stable.legacyPackages.${"x86_64-linux"}.ruby) #TODO: do better
    unzip
    cargo
    rustc
    nh
    just
    stdenv.cc.cc.lib
    luajit
    luajitPackages.luarocks
  ];

  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixconf";
    LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib";
  };
  home.sessionPath = [
    "/home/cramt/.local/share/gem/ruby/3.1.0/bin"
  ];
}
