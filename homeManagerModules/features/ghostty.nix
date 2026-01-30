{lib, ...}: {
  config = {
    stylix.targets.ghostty.enable = true;
    programs.ghostty = {
      enable = true;
      settings = {
        # Window settings
        window-decoration = false;
        window-padding-x = 0;
        window-padding-y = 0;
        
        # Behavior settings
        confirm-close-surface = false;  # No confirmation when closing
        mouse-hide-while-typing = true;  # Hide cursor while typing
      };
    };
  };
}
