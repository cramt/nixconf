{inputs, ...}: {
  hmModules.bundles.gaming = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ];
    options.myHomeManager.bundles.gaming.enable = lib.mkEnableOption "myHomeManager.bundles.gaming";
    config = lib.mkIf config.myHomeManager.bundles.gaming.enable {
      home.packages = with pkgs; [
        libxcb
        gamemode
        dxvk
        gamescope
        mangohud
        winetricks
        inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.melonds
        prismlauncher
        lutris
        heroic
        #(bottles.override {removeWarningPopup = true;})
        faugus-launcher
      ];
      services.flatpak = {
        enable = true;
        packages = [];
        # NixOS exports SSL_CERT_FILE pointing at a /nix/store CA bundle that
        # isn't mounted inside the Flatpak sandbox, which breaks TLS for every
        # flatpak (Bottles reports "You are offline"). Point flatpaks at the CA
        # bundle that actually exists inside the runtime.
        overrides.settings.global.Environment.SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      };
      myHomeManager = {
        wowup.enable = true;
        cockatrice.enable = true;
        nonsteamlauncher.enable = false;
      };
      services.xembed-sni-proxy.enable = true;
    };
  };
}
