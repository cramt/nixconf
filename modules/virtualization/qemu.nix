# QEMU/Quick Emu virtualisation
{ inputs, ... }: {
  flake.nixosModules."features.qemu" = { config, lib, pkgs, ... }: {
    options.myNixOS.qemu.enable = lib.mkEnableOption "myNixOS.qemu";
    config = lib.mkIf config.myNixOS.qemu.enable {
      # Both held on stable (qemu 10.2.4 vs 11.0.2 on unstable) — quickemu tracks
      # qemu closely, so they move as a pair. Reason for the hold predates the
      # dendritic migration and wasn't recorded; retest together, not one at a time.
      environment.systemPackages = with inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}; [
        qemu
        quickemu
      ];
    };
  };
}
