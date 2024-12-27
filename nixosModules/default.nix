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
      inputs.stylix.nixosModules.stylix
      inputs.sops-nix.nixosModules.sops
      inputs.nixos-cosmic.nixosModules.default
    ]
    ++ features
    ++ bundles
    ++ services;

  config = {
    services.udev.extraRules = ''
      # STM32F3DISCOVERY rev A/B - ST-LINK/V2
      ATTRS{idVendor}=="0483", ATTRS{idProduct}=="3748", TAG+="uaccess"

      # STM32F3DISCOVERY rev C+ - ST-LINK/V2-1
      ATTRS{idVendor}=="0483", ATTRS{idProduct}=="374b", TAG+="uaccess"
    '';
    sops = {
      defaultSopsFile = ../secrets/secrets.yaml;
      defaultSopsFormat = "yaml";
      age = {
        keyFile = "/home/cramt/.config/sops/age/keys.txt";
      };
      secrets = {
        "homelab_discord_bot/discord_token" = {};
        "homelab_discord_bot/allowed_guild" = {};
        "cockatrice/password" = {};
        "valheim/secrets" = {};
        "pap_secrets" = {};
      };
    };
    stylix.enable = true;
    nix.settings = {
      experimental-features = ["nix-command" "flakes" "pipe-operators"];
      trusted-users = ["cramt" "root"];
      substituters = [
        "https://walker.cachix.org"
        "https://walker-git.cachix.org"
        "https://cosmic.cachix.org"
      ];
      trusted-public-keys = [
        "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
        "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
        "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
      ];
    };
    programs.nix-ld.enable = true;
    nixpkgs = {
      overlays = [
        inputs.nur.overlays.default
      ];
      config = {
        allowUnfree = true;
      };
    };
  };
}
