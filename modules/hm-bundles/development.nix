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
        java.enable = true;
        scala.enable = true;
        ruby.enable = true;
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
          # pnpm 12 can't switch down to a `packageManager: pnpm@11.x` pin: it looks up
          # `@pnpm/exe.linux-x64`, but 11.x ships as `@pnpm/linux-x64` ("no
          # @pnpm/exe.linux-x64 native binary was found for this host"). No upstream
          # issue found as of 2026-11-24. Go back to `pnpm` once rezip/monorepo pins
          # pnpm 12 or pnpm 12 can switch to 11.x.
          pnpm_11
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
          inputs.chipsmith.packages.${pkgs.stdenv.hostPlatform.system}.default
          # The Quartus runner the RE repos' tools/quartus.sh call; it has to
          # share this nixpkgs, or installs it patched stop matching.
          inputs.chipsmith.packages.${pkgs.stdenv.hostPlatform.system}.chipsmith-vendor
          zig
          futhark
          agent-browser
          devenv
          geminicommit
          inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
          spade
          # Spade's build tool. The zed-spade extension runs the language
          # server as `swim lsp`, so it has to be on PATH, not just spadec.
          #
          # The Vixen extension wants `vx` on PATH the same way, and it is
          # deliberately NOT here: vixen has no nixpkgs package, and building
          # it from its own flake is 287 derivations of a fast-moving project
          # for one LSP binary. Zed resolves it through the worktree's shell
          # env, and `load_direnv = "shell_hook"` is set, so a devshell in a
          # vix project supplies it. Revisit if vixen lands in nixpkgs.
          swim
          # The Zed julia extension runs JETLS via `julia` on PATH (needs 1.12.2..1.13)
          # and installs JETLS itself into a private depot.
          julia
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
        # Every rezip terraform root kept its own ~1G copy of the AWS provider;
        # ~25 of them added up to 33G on mars. A shared cache stores each
        # provider version once and hardlinks/symlinks it into .terraform.
        TF_PLUGIN_CACHE_DIR = "${config.xdg.cacheHome}/terraform/plugins";
      };
      # terraform refuses to create the cache dir itself
      xdg.cacheFile."terraform/plugins/.keep".text = "";
    };
  };
}
