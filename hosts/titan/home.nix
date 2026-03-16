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
    openclaw.enable = true;
  };

  home.packages = [
    inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
  ];

  home.stateVersion = "25.11";
}
