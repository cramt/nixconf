{
  pkgs,
  config,
  inputs,
  lib,
  ...
}:
let
  ld_packages = with pkgs; [
    libyaml.dev
    stdenv.cc.cc
    openssl.dev
  ];
in
{
  programs.go.enable = true;

  myHomeManager = {
    opencode.enable = false;
    java.enable = true;
    ruby.enable = true;
    codex.enable = true;
  };

  home.packages =
    with pkgs;
    [
      gh
      pkg-config
      gnumake
      (lib.hiPrio gcc)
      yarn
      inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nodejs_24
      nodePackages.pnpm
      cargo
      rustfmt
      rustc
      just
      clang
      postgresql.out
      terraform
      opentofu
      tflint
      inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.awscli2
      ssm-session-manager-plugin
      gcc-arm-embedded
      #julia TODO: reenable when build doesnt fail
      zig
      futhark
      devenv
      geminicommit
      inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
      spade
      npins
      nix-prefetch-docker
    ]
    ++ ld_packages;

  home.sessionVariables = {
    LD_LIBRARY_PATH = "${lib.makeLibraryPath ld_packages}";
    LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
    CC = "${pkgs.clang}/bin/clang";
    PKG_CONFIG_PATH = lib.strings.concatStringsSep ":" (
      builtins.map (x: "${x}/lib/pkgconfig") ld_packages
    );
  };
}
