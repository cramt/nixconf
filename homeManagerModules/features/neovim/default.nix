{ pkgs, ... }: {
  config = {
  xdg.configFile."neovide/config.toml".source = ./neovide_config.toml;
    stylix.targets.nixvim.enable = false;
    stylix.targets.vim.enable = false;
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };

    home.packages = with pkgs; [
      neovide
    ];
  };
}
