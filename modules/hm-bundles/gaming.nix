{ inputs, ... }: {
  hmModules.bundles.gaming = { config, lib, pkgs, ... }: {
    imports = [
      inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ];
    options.myHomeManager.bundles.gaming.enable = lib.mkEnableOption "myHomeManager.bundles.gaming";
    config = lib.mkIf config.myHomeManager.bundles.gaming.enable {
      home.packages = with pkgs; [
        libxcb gamemode dxvk gamescope mangohud winetricks
        inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.melonDS
        prismlauncher lutris heroic
        (bottles.override {removeWarningPopup = true;})
      ];
      services.flatpak = { enable = true; packages = []; };
      myHomeManager = {
        wowup.enable = true;
        cockatrice.enable = true;
        nonsteamlauncher.enable = false;
      };
      services.xembed-sni-proxy.enable = true;
    };
  };
}
