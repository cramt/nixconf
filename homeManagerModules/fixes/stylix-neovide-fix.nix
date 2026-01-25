{ lib, config, ... }:

# Fix for Stylix using deprecated programs.neovim.extraLuaConfig
# This module overrides the stylix neovide target to use the new initLua option
{
  config = lib.mkIf (config.stylix.enable && config.programs.neovide.enable) {
    # Disable the built-in stylix neovide target
    stylix.targets.neovide.enable = lib.mkForce false;
    
    # Provide our own fixed implementation
    programs.neovide.settings.font = {
      normal = [ config.stylix.fonts.monospace.name ];
      size = config.stylix.fonts.sizes.terminal;
    };
    
    programs.neovim.initLua = ''
      if vim.g.neovide then
        vim.g.neovide_normal_opacity = ${toString config.stylix.opacity.terminal}
      end
    '';
  };
}
