{
  pkgs,
  config,
  inputs,
  lib,
  ...
}: let
  ld_packages = with pkgs; [
    libyaml.dev
    stdenv.cc.cc
    linuxPackages.nvidia_x11
  ];
in {
  imports = [
    inputs.nix-colors.homeManagerModules.default
  ];

  programs.home-manager.enable = true;
  programs.go.enable = true;

  myHomeManager = {
    yazi.enable = true;
    zoxide.enable = true;
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
    btop.enable = true;
    lazygit.enable = true;
  };

  home.packages = with pkgs;
    [
      git
      gnupg
      nushell
      zellij
      eza
      zoxide
      bat
      gnumake
      (hiPrio gcc)
      ripgrep
      sd
      fd
      neofetch
      wget
      yarn
      inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.nodejs_23
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
      awscli2
      ssm-session-manager-plugin
      dnsutils
      sops
      gcc-arm-embedded
      openocd
      inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.nvfetcher
      jq
      nix-output-monitor
      julia
      zig
    ]
    ++ ld_packages;

  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixconf";
    LD_LIBRARY_PATH = "${lib.makeLibraryPath ld_packages}";
    LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
    NEOVIDE_FORK = "1";
    EDITOR = "nvim";
    BROWSER = "zen";
    TERMINAL = "alacritty";
  };
}
