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
  (final: prev: {
    llama-cpp-rocm-rpc = prev.llama-cpp.override {
      rocmSupport = true;
      rpcSupport = true;
    };
    llama-cpp-cuda-rpc = prev.llama-cpp.override {
      cudaSupport = true;
      rpcSupport = true;
    };
  })

  (final: prev: {
    cockatrice = prev.callPackage ../packages/cockatrice {
      src = inputs.cockatrice-src;
    };
  })

  # Not in nixpkgs; built from source (Go + embedded Svelte frontend).
  # Bump version + hashes in ../packages/agentsview/default.nix.
  (final: prev: {
    agentsview = prev.callPackage ../packages/agentsview {};
  })

  # Replace nixpkgs' source-built zed-editor (lags upstream by days/weeks)
  # with the official prebuilt preview tarball. Bump version + hash in
  # ../packages/zed-bin/default.nix.
  (final: prev: {
    zed-editor = prev.callPackage ../packages/zed-bin {};
  })

  # Workaround for nixpkgs#514113: openldap 2.6.13 test017-syncreplication-refresh
  # is flaky and fails the build.
  # Remove once nixpkgs#513765 (bumps syncrepl test sleep timeouts) is merged.
  (final: prev: {
    openldap = prev.openldap.overrideAttrs {
      doCheck = !prev.stdenv.hostPlatform.isi686;
    };
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

  # TODO: remove once https://github.com/NixOS/nixpkgs/issues/523332 is fixed in unstable
  # GDM 50.0 fails to launch its greeter session ("Failed to execute child process
  # 'gnome-session'"), leaving the user staring at a blank screen with a cursor in the
  # top-left after boot. Pin the GDM stack (gdm + gnome-session + gnome-shell) to 49.x
  # from the last good nixpkgs rev — the NixOS gdm module references all three packages
  # directly (pkgs.gnome-session, pkgs.gnome-shell, plus the gdm package itself), so
  # overriding only `gdm` would leave it spawning a mismatched gnome-session 50.
  (final: prev: let
    pinned = import inputs.nixpkgs-pre-gdm50 {
      inherit (prev.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  in {
    gdm = pinned.gdm;
    gnome-session = pinned.gnome-session;
    gnome-shell = pinned.gnome-shell;
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
