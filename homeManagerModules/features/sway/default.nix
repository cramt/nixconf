{ ... }: {
  config = {
    security.polkit.enable = true;
    wayland.windowManager.sway = {
      enable = true;
      config = {
        modifier = "Mod4";
        terminal = "alacritty";
      };
    };
  };
}
