{
  pkgs,
  config,
  inputs,
  ...
}: let
  master_pkgs = import inputs.nixpkgs-master {
    system = pkgs.system;
    config = {
      allowUnfree = true;
    };
  };
in {
  home.packages = with pkgs; [
    wl-clipboard
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
    master_pkgs.antigravity
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
    network-manager-applet.enable = true;
    nautilus.enable = true;
    keymapp.enable = true;
    vscode.enable = true;
  };
}
