{ input, inputs, outputs, config, pkgs, ... }:
{

  imports = [ outputs.homeManagerModules.default ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";


  myHomeManager = {
    bundles.general.enable = true;
    git.signingKey = "D14C758B96260E88";
  };

  home.stateVersion = "24.05";
}
