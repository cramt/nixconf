{ pkgs
, config
, inputs
, ...
}: {
  home.packages = with pkgs; [
    firefox
    alacritty
    kitty
    brightnessctl
    nwg-launchers
    adwaita-qt
  ];
}
