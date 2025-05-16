{...}: {
  config = {
    stylix.targets.ghostty.enable = true;
    programs.ghostty = {
      enable = true;
      settings = {
        window-decoration = false;
        window-padding-x = 0;
        window-padding-y = 0;
      };
    };
  };
}
