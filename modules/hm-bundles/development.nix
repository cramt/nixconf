{ inputs, ... }: {
  hmModules.bundles.development = { config, lib, pkgs, ... }:
  let
    ld_packages = with pkgs; [
      libyaml.dev
      stdenv.cc.cc
      openssl.dev
    ];
  in {
    options.myHomeManager.bundles.development.enable = lib.mkEnableOption "myHomeManager.bundles.development";
    config = lib.mkIf config.myHomeManager.bundles.development.enable {
      programs.go.enable = true;
      myHomeManager = {
        claude-code.enable = true;
        opencode.enable = true;
        java.enable = true;
        ruby.enable = true;
        codex.enable = true;
      };
      home.packages = with pkgs;
        [
          gh pkg-config gnumake (lib.hiPrio gcc) yarn
          inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nodejs_24
          pnpm cargo rustfmt rustc just clang postgresql.out opentofu tflint
          inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.awscli2
          gcc-arm-embedded zig futhark devenv geminicommit
          inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
          spade npins nix-prefetch-docker sshpass codexbar
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
    };
  };
}
