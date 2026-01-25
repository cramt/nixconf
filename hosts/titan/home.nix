{
  inputs,
  outputs,
  pkgs,
  ...
}: {
  imports = [
    outputs.homeManagerModules.default
  ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    bundles.general.enable = true;
    
    clawdbot.enable = true;
  };

  home.stateVersion = "25.05";
}
