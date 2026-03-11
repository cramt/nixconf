{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nix-openclaw.homeManagerModules.openclaw
  ];

  programs.openclaw = {
    enable = true;
  };
}
