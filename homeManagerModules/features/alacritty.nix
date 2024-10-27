{pkgs, ...}: let
  zellij_smart_start = (import ../../scripts/zellij_smart_start.nix) {
    inherit pkgs;
  };
in {
  programs.alacritty = {
    enable = true;
    settings = {
      terminal.shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = ["-l" "-c" "${zellij_smart_start}/bin/zellij_smart_start"];
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
