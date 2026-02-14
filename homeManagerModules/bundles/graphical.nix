{
  pkgs,
  config,
  inputs,
  ...
}: {
  home.packages = with pkgs; [
    wl-clipboard
    alacritty
    kitty
    brightnessctl
    pavucontrol
    adwaita-qt
    gimp
    vlc
    element-desktop
    antigravity
    orca-slicer
  ];

  xdg.enable = true;

  myHomeManager = {
    ghostty.enable = true;
    git_update_notifier.enable = false;
    thunderbird.enable = false;
    cosmic.enable = true;
    alacritty.enable = true;
    rio.enable = true;
    mako.enable = true;
    zathura.enable = true;
    vesktop.enable = true;
    zed.enable = true;
    zen.enable = true;
    network-manager-applet.enable = true;
    nautilus.enable = true;
    keymapp.enable = true;
    vscode.enable = true;
  };
}
