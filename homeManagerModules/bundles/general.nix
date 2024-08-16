{ pkgs
, config
, inputs
, lib
, ...
}:
let
  ld_packages = with pkgs; [
    libyaml.dev
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
  programs.go.enable = true;

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
    zellij.enable = true;
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
    just
    clang
    postgresql.out
    terraform
    opentofu
    tflint
    #todo fix with https://github.com/NixOS/nixpkgs/issues/332957
    #awscli2
    dnsutils
    sops
  ] ++ ld_packages;

  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixconf";
    LD_LIBRARY_PATH = "${lib.makeLibraryPath ld_packages}";
    NEOVIDE_FORK = "1";
    EDITOR = "nvim";
    BROWSER = "firefox";
    TERMINAL = "alacritty";
  };
}
