{ ... }: {
  hmModules.bundles.work = { config, lib, pkgs, ... }: {
    options.myHomeManager.bundles.work.enable = lib.mkEnableOption "myHomeManager.bundles.work";
    config = lib.mkIf config.myHomeManager.bundles.work.enable {
      myHomeManager = {
        distrobox.enable = true;
      };
      home.packages = with pkgs; [
        scaleway-cli slack postgresql teams-for-linux ngrok
      ];
    };
  };
}
