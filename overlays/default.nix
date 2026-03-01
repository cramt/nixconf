inputs: [
  inputs.nur.overlays.default

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

  (final: prev: {
    julia = prev.julia.withPackages ["JuliaFormatter" "LanguageServer"];
  })

  (final: prev: {
    docker = prev.docker.override {
      buildxSupport = true;
    };
  })

  (final: prev: {
    codexbar = prev.callPackage ../packages/codexbar/default.nix {};
  })

  (final: prev: {
    rocmPackages = inputs.nixpkgs-stable.legacyPackages.${prev.stdenv.hostPlatform.system}.rocmPackages;
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
