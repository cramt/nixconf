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
    inputs.zen-browser.packages."${pkgs.system}".default
  ];

  xdg.enable = true;

  myHomeManager = {
    ghostty.enable = true;
    git_update_notifier.enable = true;
    thunderbird.enable = false;
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
