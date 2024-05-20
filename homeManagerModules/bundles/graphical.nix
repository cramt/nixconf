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
    pavucontrol
    nwg-launchers
    adwaita-qt
    gimp
    libsForQt5.okular
  ];

  myHomeManager = {
    firefox.enable = true;
    sway.enable = true;
    zellij.enable = true;
    alacritty.enable = true;
    gtk.enable = true;
    mako.enable = true;
    network-manager-applet.enable = true;
  };
}
