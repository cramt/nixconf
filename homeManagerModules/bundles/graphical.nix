{
  pkgs,
  config,
  inputs,
  ...
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
    git_update_notifier.enable = true;
    thunderbird.enable = false;
    firefox.enable = true;
    sway.enable = true;
    alacritty.enable = true;
    rio.enable = true;
    mako.enable = true;
    zathura.enable = true;
    network-manager-applet.enable = true;
    nautilus.enable = true;
    keymapp.enable = true;
  };
}
