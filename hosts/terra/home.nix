{ input, outputs, config, pkgs, ... }:
{

  imports = [outputs.homeManagerModules.default];

  programs.git = {
    enable = true;
    userName = "cramt";
    userEmail = "alex.cramt@gmail.com";
  };

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  nixpkgs.config = {
    allowUnfree = true;
  };

  myHomeManager = {
    bundles.general.enable = true;
    firefox.enable = true;
    hyprland.enable = true;
  };

  home.stateVersion = "23.11"; 

  home.sessionVariables = {
    EDITOR = "lvim";
  };
}
