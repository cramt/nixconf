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
        # Held on stable's 2026-05-17 snapshot; unstable moved to 2026-07-19.
        # Pinned deliberately in 02dca98, reason unrecorded — retest on a whim,
        # nothing else depends on it.
        inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.melonds
        lutris
        heroic
        # Legends of Runeterra. Riot's Packman anti-tamper rejects current wine
        # (int 0x2c -> STATUS_ASSERTION_FAILURE before Unity even logs), so the
        # package pins GE-Proton8-27-LoL and sets up DXVK + the prefix itself.
        # https://github.com/cramt/lor-on-linux
        inputs.nix-games.packages.${pkgs.stdenv.hostPlatform.system}.legends-of-runeterra
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
        prismlauncher.enable = true;
        wowup.enable = true;
        cockatrice.enable = true;
      };
      services.xembed-sni-proxy.enable = true;
    };
  };
}
