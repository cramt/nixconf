{ pkgs
, config
, inputs
, lib
, ...
}:
let
  ld_packages = with pkgs; [
    libyaml
    stdenv.cc.cc.lib
  ];
in
{
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
    vesktop.enable = true;
    nushell.enable = true;
    ruby.enable = true;
  };

  home.packages = with pkgs; [
    git
    gnupg
    nushell
    zellij
    htop
    eza
    zoxide
    bat
    gnumake
    (hiPrio gcc)
    ripgrep
    neofetch
    lazygit
    wget
    nodejs_20
    yarn
    nodePackages.pnpm
    unzip
    cargo
    rustc
    nh
    just
    luajit
    luajitPackages.luarocks
    clang
    postgresql.out
    terraform
    tflint
    awscli2
  ] ++ ld_packages;

  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixconf";
    LD_LIBRARY_PATH = "${lib.makeLibraryPath ld_packages}";
    NEOVIDE_FORK = "1";
  };
}
