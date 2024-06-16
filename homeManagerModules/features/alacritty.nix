{ pkgs, ... }: {
  programs.alacritty = {
    enable = true;
    settings = {
      shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = [ "-l" "-c" "${pkgs.zellij}/bin/zellij attach --index 0 || ${pkgs.zellij}/bin/zellij" ];
      };
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
