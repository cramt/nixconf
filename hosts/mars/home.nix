{ input, inputs, outputs, config, pkgs, ... }:
{

  imports = [ outputs.homeManagerModules.default ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";


  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-dark-medium;

  myHomeManager = {
    bundles.general.enable = true;
    bundles.graphical.enable = true;
    git.signingKey = "5A2AFD974351E6CA";
    sway.monitors = {
      eDP-1 = {
        pos = "0 0";
        res = "1920x1200";
        workspace = "1";
      };
      HDMI-A-1 = {
        pos = "-3440 -800";
        res = "3440x1440";
        workspace = "2";
      };
      DP-6 = {
        pos = "-5600 -2600";
        res = "3840x2160";
        transform = "270";
        workspace = "3";
      };
    };
  };

  home.stateVersion = "23.11";

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
