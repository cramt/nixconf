{ inputs, ... }:
let
  npinsSources = import ../../npins;
in
{
  perSystem = { pkgs, ... }: {
    packages.t3code = pkgs.callPackage ../../packages/t3code/default.nix {
      npinsSources = builtins.mapAttrs (_: x: x {}) npinsSources;
    };

    packages.pi-coding-agent = pkgs.callPackage ../../packages/pi-coding-agent/default.nix {};

    packages.eros-img = pkgs.runCommand "eros-img" {} ''
      ${pkgs.zstd}/bin/unzstd -d \
        ${inputs.self.nixosConfigurations.eros.config.system.build.images.sd-card}/sd-image/* \
        -o $out
    '';
  };
}
