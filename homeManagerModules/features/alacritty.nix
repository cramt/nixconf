{...}: {
  programs.alacritty = {
    enable = true;
    settings = {
      colors = {
        draw_bold_text_with_bright_colors = true;
      };
      mouse = {
        hide_when_typing = true;
      };
      window = {
        decorations_theme_variant = "Dark";
        dynamic_padding = true;
      };
    };
  };
}
