let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
in
builtins.mapAttrs (n: v: (import v)) (
  lib.attrsets.filterAttrs (n: v: builtins.pathExists v) (
    builtins.mapAttrs (n: _: ./hosts/${n}/ssh.pub.nix) (
      lib.attrsets.filterAttrs (n: v: v == "directory") (
        builtins.readDir ./hosts
      )
    )
  )
)

