{ pkgs
, config
, inputs
, ...
}: {
  home.packages = with pkgs; [
    alacritty
    kitty
    brightnessctl
    pavucontrol
    adwaita-qt
    gimp
  ];

  xdg.enable = true;

  myHomeManager = {
    thunderbird.enable = true;
    firefox.enable = true;
    sway.enable = true;
    alacritty.enable = true;
    mako.enable = true;
    zathura.enable = true;
    network-manager-applet.enable = true;
    nautilus.enable = true;
  };
}
