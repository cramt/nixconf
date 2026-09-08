{inputs, ...}: {
  hmModules.bundles.gaming = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.myHomeManager.bundles.gaming.enable = lib.mkEnableOption "myHomeManager.bundles.gaming";
    config = lib.mkIf config.myHomeManager.bundles.gaming.enable {
      home.packages = with pkgs; [
        libxcb
        gamemode
        dxvk
        gamescope
        mangohud
        # Legends of Runeterra. Riot's Packman anti-tamper rejects current wine
        # (int 0x2c -> STATUS_ASSERTION_FAILURE before Unity even logs), so the
        # package pins GE-Proton8-27-LoL and sets up DXVK + the prefix itself.
        # https://github.com/cramt/lor-on-linux
        inputs.nix-games.packages.${pkgs.stdenv.hostPlatform.system}.legends-of-runeterra
      ];
      myHomeManager = {
        prismlauncher.enable = true;
        cockatrice.enable = true;
      };
    };
  };
}
