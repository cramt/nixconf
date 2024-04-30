{ pkgs, ... }: {
  home.packages = with pkgs; [
    xorg.libxcb
    lutris
    protonup-ng
    gamemode
    dxvk
    gamescope
    mangohud
    (wineWowPackages.full.override {
      wineRelease = "staging";
      mingwSupport = true;
    })
    winetricks
    melonDS
  ];
}
