{ ... }: {
  hmModules.features.obs = { config, lib, pkgs, ... }: {
    options.myHomeManager.obs.enable = lib.mkEnableOption "myHomeManager.obs";
    config = lib.mkIf config.myHomeManager.obs.enable {
      programs.obs-studio = {
        enable = true;
        plugins = with pkgs.obs-studio-plugins; [
          wlrobs obs-pipewire-audio-capture obs-vaapi obs-gstreamer obs-vkcapture
        ];
      };
    };
  };
}
