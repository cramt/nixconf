{ input, inputs, outputs, config, pkgs, ... }:
{

  imports = [ outputs.homeManagerModules.default ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    bundles.general.enable = true;
    neovim.enable = true;
    firefox.enable = true;
    sway.enable = true;
    zsh.enable = true;
    ssh.enable = true;
    git.enable = true;
    git.signingKey = "EE5C69A3E36D0A2B";
    starship.enable = true;
  };

  home.stateVersion = "23.11";

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
