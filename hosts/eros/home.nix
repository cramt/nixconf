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
  };

  home.stateVersion = "25.11";
}
