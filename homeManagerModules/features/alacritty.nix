{ pkgs, ... }: {
  programs.alacritty = {
    enable = true;
    settings = {
      shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = [ "-l" "-c" "${pkgs.zellij}/bin/zellij attach --index 0 || ${pkgs.zellij}/bin/zellij" ];
      };
      font = {
        size = 8.5;
      };
      colors = {
        draw_bold_text_with_bright_colors = true;
      };
      mouse = {
        hide_when_typing = true;
      };
      window = {
        opacity = 0.6;
        decorations_theme_variant = "Dark";
        dynamic_padding = true;
      };
    };
  };
}
