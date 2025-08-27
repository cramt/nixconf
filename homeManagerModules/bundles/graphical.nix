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
    anytype
    vlc
    element-desktop
  ];

  xdg.enable = true;

  myHomeManager = {
    ghostty.enable = true;
    git_update_notifier.enable = true;
    thunderbird.enable = false;
    hyprland.enable = true;
    cosmic.enable = false;
    alacritty.enable = true;
    rio.enable = true;
    mako.enable = true;
    zathura.enable = true;
    vesktop.enable = true;
    zed.enable = true;
    network-manager-applet.enable = true;
    nautilus.enable = true;
    keymapp.enable = true;
    vscode.enable = true;
  };
}
