{ pkgs, ... }: {
  home.packages = with pkgs; [
    xorg.libxcb
    lutris
    protonup-ng
    gamemode
    dxvk
    gamescope
    mangohud
    wineWowPackages.staging
    winetricks
  ];
}
