{ pkgs, ... }: {
  programs.alacritty = {
    enable = true;
    settings = {
      shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = [ "-l" "-c" "${pkgs.zellij}/bin/zellij attach --index 0 || ${pkgs.zellij}/bin/zellij" ];
      };
    };
  };
}
