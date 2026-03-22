{ ... }: {
  hmModules.features.zellij = { config, lib, pkgs, ... }: {
    options.myHomeManager.zellij.enable = lib.mkEnableOption "myHomeManager.zellij";
    config = lib.mkIf config.myHomeManager.zellij.enable {
      home.packages = [
        ((import ../../scripts/zellij_smart_start.nix) { inherit pkgs; })
      ];
      programs.zellij = {
        enable = true;
        settings = {
          show_startup_tips = false;
          pane_frames = false;
          session_serialization = false;
          pane_viewport_serialization = false;
        };
      };
    };
  };
}
