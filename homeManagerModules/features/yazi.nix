{...}: {
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    yaziPlugins = {
      enable = true;
      plugins = {
      };
    };

    settings = {
      manager = {
        show_hidden = true;
      };
    };
  };
}
