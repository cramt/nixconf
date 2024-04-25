{ pkgs, ... }: {
  home.packages = with pkgs; [
    xorg.libxcb
    lutris
    protonup-ng
    gamemode
    dxvk
    # parsec-bin

    gamescope

    # heroic
    mangohud
  ];
}
