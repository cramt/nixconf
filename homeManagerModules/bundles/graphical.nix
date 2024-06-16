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
    adwaita-qt
    gimp
  ];

  myHomeManager = {
    firefox.enable = true;
    sway.enable = true;
    zellij.enable = true;
    alacritty.enable = true;
    gtk.enable = true;
    mako.enable = true;
    zathura.enable = true;
    network-manager-applet.enable = true;
  };
}
