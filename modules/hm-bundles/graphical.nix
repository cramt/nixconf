{ ... }: {
  hmModules.bundles.graphical = { config, lib, pkgs, ... }: {
    options.myHomeManager.bundles.graphical.enable = lib.mkEnableOption "myHomeManager.bundles.graphical";
    config = lib.mkIf config.myHomeManager.bundles.graphical.enable {
      home.packages = with pkgs; [
        wl-clipboard alacritty kitty brightnessctl pavucontrol adwaita-qt gimp vlc element-desktop antigravity orca-slicer
      ];
      xdg.enable = true;
      # Keep the Orca screen reader off declaratively. COSMIC/GDM pull in the
      # a11y stack, and Super+Alt+S can toggle it on by accident; without this
      # the toggle persists as runtime-only dconf state.
      dconf.settings."org/gnome/desktop/a11y/applications".screen-reader-enabled = false;
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
    };
  };
}
