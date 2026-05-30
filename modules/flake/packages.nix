{ inputs, ... }:
{
  perSystem = { pkgs, lib, system, ... }: {
    packages = {
      t3code = pkgs.callPackage ../../packages/t3code/default.nix {};
    } // lib.optionalAttrs (system == "x86_64-linux") {
      # OpenWrt sysupgrade image for the Archer C5 v2 (host: titan). The upstream
      # ImageBuilder ships only x86_64-linux binaries, so gate accordingly.
      titan-img = import ../../hosts/titan/configuration.nix { inherit pkgs inputs; };

      # Dewclaw deployment environment for titan. `nix build .#titan-deploy`
      # produces a buildEnv whose `bin/` contains a deploy-titan script that
      # SSHes into the router and applies the UCI config declared in
      # hosts/titan/dewclaw.nix.
      titan-deploy = pkgs.callPackage inputs.dewclaw {
        configuration = import ../../hosts/titan/dewclaw.nix;
      };

      # Custom / from-source derivations that Hydra never caches (overlay
      # patches, ROCm/CUDA builds). Pulled straight from saturn's overlaid
      # package set so the store paths are byte-identical to what the x86
      # hosts build. CI prebuilds these and pushes them to cachix so the
      # toplevel builds substitute instead of compiling for hours.
      inherit
        (inputs.self.nixosConfigurations.saturn.pkgs)
        cosmic-comp
        llama-cpp-rocm-rpc
        llama-cpp-cuda-rpc
        ;
    } // lib.optionalAttrs (system == "aarch64-linux") {
      # Steam Link client — aarch64 only because it's a prebuilt arm64 binary.
      steamlink = pkgs.callPackage ../../packages/steamlink {};

      # nixos-raspberrypi exposes the SD image at config.system.build.sdImage
      # (instead of the upstream installer's `images.sd-card` path). aarch64
      # only — eros is a Raspberry Pi, so building this on x86 would emulate.
      eros-img = pkgs.runCommand "eros-img" {} ''
        ${pkgs.zstd}/bin/unzstd -d \
          ${inputs.self.nixosConfigurations.eros.config.system.build.sdImage}/sd-image/* \
          -o $out
      '';
    };
  };
}
