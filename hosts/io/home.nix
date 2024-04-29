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
  };

  home.stateVersion = "23.11";

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
