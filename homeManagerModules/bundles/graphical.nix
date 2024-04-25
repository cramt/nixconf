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

  myHomeManager = {
    firefox.enable = true;
    sway.enable = true;
    zellij.enable = true;
    alacritty.enable = true;
    gtk.enable = true;
    mako.enable = true;
  };
}
