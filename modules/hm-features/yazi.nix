{ ... }: {
  hmModules.features.yazi = { config, lib, pkgs, ... }: {
    options.myHomeManager.yazi.enable = lib.mkEnableOption "myHomeManager.yazi";
    config = lib.mkIf config.myHomeManager.yazi.enable {
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        shellWrapperName = "y";
        plugins = {
          inherit (pkgs.yaziPlugins) glow mount smart-enter;
        };
        keymap = {
          manager = {
            prepend_keymap = [
              { on = "M"; run = "plugin mount"; }
              { on = "<Left>"; run = "plugin fast-enter"; desc = "enter"; }
            ];
          };
        };
        settings = {
          manager.show_hidden = true;
          plugin.prepend_previewers = [
            { name = "*.md"; run = "glow"; }
          ];
        };
      };
    };
  };
}
