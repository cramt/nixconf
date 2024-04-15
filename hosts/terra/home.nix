{ input, inputs, outputs, config, pkgs, ... }:
{

  imports = [ outputs.homeManagerModules.default ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    bundles.general.enable = true;
    neovim.enable = true;
    firefox.enable = true;
    hyprland.enable = true;
    zsh.enable = true;
    ssh.enable = true;
    git.enable = true;
    git.signingKey = "TEST";
  };

  home.stateVersion = "23.11";

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
