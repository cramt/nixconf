{
  pkgs,
  config,
  lib,
  inputs,
  outputs,
  myLib,
  ...
}: let
  cfg = config.myNixOS;

  # Taking all modules in ./features and adding enables to them
  features =
    myLib.extendModules
    (name: {
      extraOptions = {
        myNixOS.${name}.enable = lib.mkEnableOption "enable my ${name} configuration";
      };

      configExtension = config: (lib.mkIf cfg.${name}.enable config);
    })
    (myLib.filesIn ./features);

  # Taking all module bundles in ./bundles and adding bundle.enables to them
  bundles =
    myLib.extendModules
    (name: {
      extraOptions = {
        myNixOS.bundles.${name}.enable = lib.mkEnableOption "enable ${name} module bundle";
      };

      configExtension = config: (lib.mkIf cfg.bundles.${name}.enable config);
    })
    (myLib.filesIn ./bundles);

  services =
    myLib.extendModules
    (name: {
      extraOptions = {
        myNixOS.services.${name}.enable = lib.mkEnableOption "enable ${name} service";
      };

      configExtension = config: (lib.mkIf cfg.services.${name}.enable config);
    })
    (myLib.filesIn ./services);
in {
  imports =
    [
      inputs.home-manager.nixosModules.home-manager
      inputs.chaotic.nixosModules.default
      inputs.stylix.nixosModules.stylix
      inputs.foundryvtt.nixosModules.foundryvtt
      inputs.nixarr.nixosModules.default
      ../portselector.nix
    ]
    ++ features
    ++ bundles
    ++ services;

  config = {
    stylix.enable = true;
    services.gnome.gcr-ssh-agent.enable = false;
    nix.package = pkgs.lix;
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["cramt" "root"];
      substituters = [
        "https://nix-gaming.cachix.org"
        "https://yazi.cachix.org"
        "https://nvf.cachix.org"
      ];
      trusted-public-keys = [
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
        "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
        "nvf.cachix.org-1:GMQWiUhZ6ux9D5CvFFMwnc2nFrUHTeGaXRlVBXo+naI="
      ];
    };
    programs.nix-ld.enable = true;
    nixpkgs = {
      overlays = [
        inputs.nur.overlays.default
        (final: prev: let
          sources = import ../npins;
          system = pkgs.system;
          npinspkgs = import sources.nixpkgs {
            inherit system;
          };
          rest = builtins.removeAttrs sources ["nixpkgs"];
        in {
          npins = builtins.mapAttrs (_: x: x {pkgs = npinspkgs;}) rest;
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
          rocmPackages = inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.rocmPackages;
        })
        (final: prev: {
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
      ];
      config = {
        allowUnfree = true;
      };
    };
  };
}
