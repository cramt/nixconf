inputs: [
  inputs.nur.overlays.default

  # Exposes niri-stable/niri-unstable and xwayland-satellite-stable/-unstable
  # under pkgs.*. We use niri-stable (v25.08) + xwayland-satellite-stable, which
  # have niri's integrated xwayland-satellite support (no manual DISPLAY juggling).
  inputs.niri-flake.overlays.niri

  # noctalia 5.x (native Wayland+GLES rewrite, no longer quickshell). Exposes
  # `pkgs.noctalia` (v5) — distinct from nixpkgs' older quickshell-based
  # `pkgs.noctalia-shell` (4.7.x), which is left untouched. We consume pkgs.noctalia
  # to match the v5 homeModule we import (modules/hm-base/default-hm.nix). The v5
  # shell avoids the quickshell layer-shell-over-IPC crash that cosmic-comp
  # triggers on multi-output setups.
  inputs.noctalia-shell.overlays.default

  (final: prev: let
    sources = import ../npins;
    npinspkgs = import sources.nixpkgs {
      inherit (prev.stdenv.hostPlatform) system;
    };
    rest = builtins.removeAttrs sources ["nixpkgs" "__functor"];
  in {
    npinsSources = builtins.mapAttrs (_: x: x {pkgs = npinspkgs;}) rest;
  })

  (final: prev: {
    lazygit = prev.writeScriptBin "lazygit" ''
      echo 'a' | ${prev.gnupg}/bin/gpg --sign -u alex.cramt@gmail.com > /dev/null && ${prev.lazygit}/bin/lazygit
    '';
  })

  (final: prev: {
    cosmic-comp = prev.cosmic-comp.overrideAttrs (old: {
      patches = (old.patches or []) ++ [../patches/no_ssd.patch];
      doCheck = false;
    });
  })

  # Shared definitions for the GPU-accelerated llama.cpp builds used by the
  # llama-cpp / llama-cpp-rpc services. These are cache misses by construction
  # (Hydra doesn't build ROCm/CUDA variants), so they're exposed as flake
  # packages (modules/flake/packages.nix) and prebuilt in CI. Keeping the
  # override here means the service modules and the prebuilt flake packages
  # resolve to the exact same store path.
  (final: prev: let
    # nixpkgs' llama-cpp rpcSupport post-install still runs
    # `cp bin/rpc-server $out/bin/llama-rpc-server`, but upstream llama.cpp
    # renamed that binary to `ggml-rpc-server` (cmake installs it under that
    # name). Bridge the old name in the build tree so the copy succeeds and the
    # service still finds `$out/bin/llama-rpc-server`. Guarded so it becomes a
    # no-op once nixpkgs catches up to the rename.
    withRpcServerFix = pkg:
      pkg.overrideAttrs (old: {
        postBuild =
          (old.postBuild or "")
          + ''
            if [ ! -e bin/rpc-server ] && [ -e bin/ggml-rpc-server ]; then
              ln -s ggml-rpc-server bin/rpc-server
            fi
          '';
      });
  in {
    llama-cpp-rocm-rpc = withRpcServerFix (prev.llama-cpp.override {
      rocmSupport = true;
      rpcSupport = true;
    });
    llama-cpp-cuda-rpc = withRpcServerFix (prev.llama-cpp.override {
      cudaSupport = true;
      rpcSupport = true;
    });
  })

  (final: prev: {
    cockatrice = prev.callPackage ../packages/cockatrice {};
  })

  # Not in nixpkgs; built from source (Go + embedded Svelte frontend).
  # Bump version + hashes in ../packages/agentsview/default.nix.
  (final: prev: {
    agentsview = prev.callPackage ../packages/agentsview {};
  })

  # nixpkgs now ships its own agent-browser (0.27.0) which lags the version we
  # track. Point pkgs.agent-browser at our local build so every consumer
  # (development bundle, claude-code feature) resolves to the same store path
  # and home-manager's buildEnv doesn't see two conflicting versions.
  # Bump version + hash in ../packages/agent-browser/default.nix.
  (final: prev: {
    agent-browser = prev.callPackage ../packages/agent-browser {};
  })

  (final: prev: {
    scaleway-cli = prev.scaleway-cli.overrideAttrs (old: {
      doCheck = false;
    });
  })

  (final: prev: {
    julia = prev.julia.withPackages ["JuliaFormatter" "LanguageServer"];
  })

  (final: prev: {
    docker = prev.docker.override {
      buildxSupport = true;
    };
  })

  # Fix faugus-launcher subprocess calls: faugus-run invokes `sys.executable -m faugus.components`
  # which spawns bare python3 without site-packages, so deps like `requests` are missing.
  # Workaround for nixpkgs#423927 (buildPythonPackage incomplete wrapping).
  (final: prev: let
    py3 = prev.python3;
    faugusDeps = with py3.pkgs; [
      pillow
      psutil
      pygobject3
      requests
      vdf
    ];
  in {
    faugus-launcher = prev.faugus-launcher.overrideAttrs (old: {
      preFixup = (old.preFixup or "") + ''
        makeWrapperArgs+=(--prefix PYTHONPATH : "$out/${py3.sitePackages}:${py3.pkgs.makePythonPath faugusDeps}")
      '';
    });
  })

  (final: prev: {
    rocmPackages = inputs.nixpkgs-stable.legacyPackages.${prev.stdenv.hostPlatform.system}.rocmPackages;
  })

  # TEMPORARY: nixos-unstable's vesktop (1.6.5) builds against electron_40, which
  # is now EOL — nixpkgs refuses electron <41 as insecure, so plain pkgs.vesktop
  # fails to evaluate. nixpkgs PR #542528 (approved + mergeable) switches vesktop
  # to the supported electron_42, relaxing its exact electron-major assertion to a
  # `>=` check so the released 1.6.5 runs on 42. Pull vesktop from that PR branch
  # (the nixpkgs-vesktop-electron42 flake input) until it lands in nixos-unstable,
  # then DELETE this overlay + the input and go back to plain pkgs.vesktop.
  # Track: https://github.com/NixOS/nixpkgs/pull/542528
  (final: prev: {
    vesktop = inputs.nixpkgs-vesktop-electron42.legacyPackages.${prev.stdenv.hostPlatform.system}.vesktop;
  })

  (pkgs: prev: {
    ttyd = prev.ttyd.overrideAttrs (final: prev: {
      nativeBuildInputs =
        (prev.nativeBuildInputs or [])
        ++ [
          pkgs.nodejs
          pkgs.yarn-berry_3
        ];
      updateAutotoolsGnuConfigScriptsPhase =
        ''
          cd html
          export HOME=$(mktemp -d)
          rm -rf ./.yarn/cache
          mkdir -p ./.yarn
          cp -r --reflink=auto ${pkgs.yarn-berry_3.fetchYarnBerryDeps {
            src = "${final.src}/html";
            hash = "sha256-2VhypFRl195JJ9+AYDC/yZhLpFjKZcSLA1sZ25IYh1g=";
          }}/cache ./.yarn/cache
          chmod u+w -R ./.yarn/cache
          yarn config set enableTelemetry false
          yarn config set enableGlobalCache false
          yarn install --mode=skip-build --inline-builds
          yarn run build
          cd ..
        ''
        + (prev.updateAutotoolsGnuConfigScriptsPhase or "");
      patches =
        (prev.patches or [])
        ++ [
          (pkgs.writeText
            "main.patch"
            ''

              diff --git a/html/src/style/index.scss b/html/src/style/index.scss
              index 0f9244b..9bf0dda 100644
              --- a/html/src/style/index.scss
              +++ b/html/src/style/index.scss
              @@ -11,8 +11,16 @@ body {
                 height: 100%;
                 margin: 0 auto;
                 padding: 0;
              +
                 .terminal {
                   padding: 5px;
                   height: calc(100% - 10px);
                 }
               }
              +
              +@font-face {
              +  font-family: 'Iosevka';
              +  font-style: normal;
              +  font-weight: normal;
              +  src: url('${pkgs.iosevka}/share/fonts/truetype/Iosevka-Regular.ttf');
              +}
              diff --git a/html/webpack.config.js b/html/webpack.config.js
              index 18bfcf3..94e0b33 100644
              --- a/html/webpack.config.js
              +++ b/html/webpack.config.js
              @@ -29,6 +29,10 @@ const baseConfig = {
                               test: /\.s?[ac]ss$/,
                               use: [devMode ? 'style-loader' : MiniCssExtractPlugin.loader, 'css-loader', 'sass-loader'],
                           },
              +            {
              +                test: /\.(ttf|otf|eot|woff|woff2)$/,
              +                type: 'asset/inline',
              +            },
                       ],
                   },
                   resolve: {
            '')
        ];
    });
  })
]
