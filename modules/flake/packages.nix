{ inputs, ... }:
{
  perSystem = { pkgs, lib, ... }: {
    packages = {
      t3code = pkgs.callPackage ../../packages/t3code/default.nix {};

      # nixos-raspberrypi exposes the SD image at config.system.build.sdImage
      # (instead of the upstream installer's `images.sd-card` path).
      eros-img = pkgs.runCommand "eros-img" {} ''
        ${pkgs.zstd}/bin/unzstd -d \
          ${inputs.self.nixosConfigurations.eros.config.system.build.sdImage}/sd-image/* \
          -o $out
      '';
    } // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "aarch64-linux") {
      # Steam Link client — aarch64 only because it's a prebuilt arm64 binary.
      steamlink = pkgs.callPackage ../../packages/steamlink {};
    };
  };
}
