{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.eros-img = pkgs.runCommand "eros-img" {} ''
      ${pkgs.zstd}/bin/unzstd -d \
        ${inputs.self.nixosConfigurations.eros.config.system.build.images.sd-card}/sd-image/* \
        -o $out
    '';
  };
}
