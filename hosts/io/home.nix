{ input, inputs, outputs, config, pkgs, ... }:
{

  imports = [ outputs.homeManagerModules.default ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";


  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-dark-medium;

  myHomeManager = {
    bundles.general.enable = true;
    bundles.graphical.enable = true;
    bundles.gaming.enable = true;
    git.signingKey = "C2B9D34D979B6063";
    sway.monitors = {
      HDMI-A-1 = {
        pos = "0 0";
        res = "1920x1080";
        workspace = "1";
        max_render_time = "5";
      };
      DVI-D-1 = {
        pos = "1920 0";
        res = "1680x1050";
        workspace = "2";
        max_render_time = "5";
      };
    };
  };

  home.stateVersion = "23.11";

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
