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
  programs.go.enable = true;

  myHomeManager = {
    opencode.enable = true;
    java.enable = true;
    ruby.enable = true;
  };

  home.packages = with pkgs;
    [
      gh
      pkg-config
      gnumake
      (hiPrio gcc)
      yarn
      inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.nodejs_24
      nodePackages.pnpm
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
      gcc-arm-embedded
      julia
      zig
      futhark
      devenv
      gemini-cli
      geminicommit
    ]
    ++ ld_packages;

  home.sessionVariables = {
    LD_LIBRARY_PATH = "${lib.makeLibraryPath ld_packages}";
    LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
    CC = "${pkgs.clang}/bin/clang";
    PKG_CONFIG_PATH = lib.strings.concatStringsSep ":" (builtins.map (x: "${x}/lib/pkgconfig") ld_packages);
  };
}
