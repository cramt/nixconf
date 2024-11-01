{...}: {
  programs.walker = {
    enable = true;
    runAsService = true;
    config = {
      force_keyboard_focus = true;
    };
  };
}
