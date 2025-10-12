{
  pkgs,
  config,
  inputs,
  lib,
  ...
}: {
  imports = [
    inputs.nix-colors.homeManagerModules.default
  ];

  programs.home-manager.enable = true;

  nix.settings = {
    access-tokens = ["github.com=${(import ../../secrets.nix).github_read_token}"];
  };

  myHomeManager = {
    yazi.enable = true;
    zoxide.enable = true;
    neovim.enable = true;
    zsh.enable = true;
    ssh.enable = true;
    git.enable = true;
    nix-index.enable = true;
    starship.enable = true;
    nushell.enable = true;
    zellij.enable = true;
    btop.enable = true;
    lazygit.enable = true;
    fzf.enable = true;
  };

  home.packages = with pkgs; [
    git
    gnupg
    nushell
    zellij
    eza
    zoxide
    bat
    ripgrep
    sd
    fd
    neofetch
    wget
    unzip
    dnsutils
    nix-output-monitor
    jq
  ];

  home.sessionVariables = {
    NH_FLAKE = "${config.home.homeDirectory}/nixconf";
    EDITOR = "nvim";
    BROWSER = "zen";
    TERMINAL = "alacritty";
  };
}
