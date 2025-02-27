{
  pkgs,
  inputs,
  ...
}: {
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    package = inputs.yazi.packages.${pkgs.system}.default;
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
