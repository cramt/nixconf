{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.t3code = pkgs.callPackage ../packages/t3code/default.nix {};

    packages.eros-img = pkgs.runCommand "eros-img" {} ''
      ${pkgs.zstd}/bin/unzstd -d \
        ${inputs.self.nixosConfigurations.eros.config.system.build.images.sd-card}/sd-image/* \
        -o $out
    '';
  };
}
