{
  description = "Stoatchat - deploy a Revolt-based chat instance via Podman Quadlet";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
  };

  outputs = {
    quadlet-nix,
    ...
  }: let
    module = {
      imports = [
        quadlet-nix.nixosModules.quadlet
        ./module.nix
      ];
    };
  in {
    nixosModules = {
      stoatchat = module;
      default = module;
    };
  };
}
