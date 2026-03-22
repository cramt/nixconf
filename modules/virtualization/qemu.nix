# QEMU/Quick Emu virtualisation
{ inputs, ... }: {
  flake.nixosModules."features.qemu" = { config, lib, pkgs, ... }: {
    options.myNixOS.qemu.enable = lib.mkEnableOption "myNixOS.qemu";
    config = lib.mkIf config.myNixOS.qemu.enable {
      environment.systemPackages = with inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}; [
        qemu
        quickemu
      ];
    };
  };
}
