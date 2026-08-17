{inputs, ...}: {
  hmModules.bundles.development = {
    config,
    lib,
    pkgs,
    ...
  }: let
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
        # Pools the Claude subscription accounts behind one local endpoint; the
        # `claude` wrapper in claude-code.nix picks this up automatically, and
        # degrades to the direct OAuth login on a host whose pool is still
        # empty. Accounts are added once each with `agent-accounts add`
        # (interactive OAuth), which Nix can't do for us.
        cli-proxy-api.enable = true;
        pi.enable = true;
        java.enable = true;
        scala.enable = true;
        ruby.enable = true;
        codex.enable = true;
        herdr.enable = true;
      };
      home.packages = with pkgs;
        [
          chromium
          gh
          pkg-config
          gnumake
          (lib.hiPrio gcc)
          yarn
          nodejs_24
          pnpm
          # One toolchain for everything, including the wasm32-wasip2 target Zed
          # needs to build dev extensions (see the fenix input in flake.nix).
          (let
            fenix = inputs.fenix.packages.${pkgs.stdenv.hostPlatform.system};
          in
            fenix.combine [
              fenix.stable.rustc
              fenix.stable.cargo
              fenix.stable.rustfmt
              fenix.stable.clippy
              fenix.stable.rust-src
              fenix.targets.wasm32-wasip2.stable.rust-std
            ])
          just
          clang
          postgresql.out
          opentofu
          tflint
          # Deliberate downgrade (stable 2.34.24 vs unstable 2.35.11) carried over
          # from before the dendritic migration; the original reason wasn't
          # recorded. Try dropping the pin next time work AWS access is handy.
          inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.awscli2
          gcc-arm-embedded
          zig
          futhark
          agent-browser
          devenv
          geminicommit
          inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
          spade
          npins
          nix-prefetch-docker
          sshpass
          cachix
        ]
        ++ ld_packages;
      home.sessionVariables = {
        LD_LIBRARY_PATH = "${lib.makeLibraryPath ld_packages}";
        LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
        CC = "${pkgs.clang}/bin/clang";
        PKG_CONFIG_PATH = lib.strings.concatStringsSep ":" (
          builtins.map (x: "${x}/lib/pkgconfig") ld_packages
        );
        AGENT_BROWSER_SKILLS_DIR = "${pkgs.agent-browser}/share/agent-browser/skills";
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };
    };
  };
}
