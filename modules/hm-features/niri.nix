{ ... }: {
  hmModules.features.niri = { config, lib, pkgs, ... }: {
    options.myHomeManager.niri.enable = lib.mkEnableOption "myHomeManager.niri";
    config = lib.mkIf config.myHomeManager.niri.enable {
      programs.niri.settings = {
        spawn-at-startup = [
          [ "${pkgs.noctalia-shell}/bin/noctalia-shell" ]
        ];
        xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;
        input.keyboard.xkb.layout = "dk";
        layout.gaps = 5;
        binds = {
          "Mod+Return".spawn-sh = lib.getExe pkgs.ghostty;
          "Mod+Q".close-window = null;
          "Mod+S".spawn-sh = "${pkgs.noctalia-shell}/bin/noctalia-shell ipc call launcher toggle";
        };
      };
    };
  };
}
