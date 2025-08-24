{
  input,
  inputs,
  outputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    outputs.homeManagerModules.default
  ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    bundles.general.enable = true;
  };

  home.stateVersion = "25.05";
}
