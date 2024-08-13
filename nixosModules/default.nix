{ pkgs
, config
, lib
, inputs
, outputs
, myLib
, ...
}:
let
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
in
{
  imports =
    [
      inputs.home-manager.nixosModules.home-manager
      inputs.stylix.nixosModules.stylix
      inputs.sops-nix.nixosModules.sops
    ]
    ++ features
    ++ bundles
    ++ services;

  config = {
    sops = {
      defaultSopsFile = ../secrets/secrets.yaml;
      defaultSopsFormat = "yaml";
      age = {
        keyFile = "/home/cramt/.config/sops/age/keys.txt";
      };
      secrets = {
        "homelab_discord_bot/discord_token" = { };
        "homelab_discord_bot/allowed_guild" = { };
      };
    };
    stylix.enable = true;
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "cramt" "root" ];
      substituters = [ "https://walker.cachix.org" ];
      trusted-public-keys = [ "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM=" ];
    };
    programs.nix-ld.enable = true;
    nixpkgs.config.allowUnfree = true;
  };
}
