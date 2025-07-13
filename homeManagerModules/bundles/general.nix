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
    openssl.dev
  ];
in {
  imports = [
    inputs.nix-colors.homeManagerModules.default
  ];

  programs.home-manager.enable = true;
  programs.go.enable = true;

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
    java.enable = true;
    vesktop.enable = true;
    nushell.enable = true;
    ruby.enable = true;
    zellij.enable = true;
    btop.enable = true;
    lazygit.enable = true;
    zed.enable = true;
  };

  home.packages = with pkgs;
    [
      pkg-config
      element-desktop
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
      inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.nodejs_24
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
      inputs.nixpkgs-ancient.legacyPackages.${pkgs.system}.nvfetcher
      jq
      nix-output-monitor
      julia
      zig
      futhark
      devenv
      gemini-cli
      geminicommit
    ]
    ++ ld_packages;

  home.sessionVariables = {
    NH_FLAKE = "${config.home.homeDirectory}/nixconf";
    LD_LIBRARY_PATH = "${lib.makeLibraryPath ld_packages}";
    LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
    CC = "${pkgs.clang}/bin/clang";
    PKG_CONFIG_PATH = lib.strings.concatStringsSep ":" (builtins.map (x: "${x}/lib/pkgconfig") ld_packages);
    EDITOR = "nvim";
    BROWSER = "zen";
    TERMINAL = "alacritty";
  };
}
