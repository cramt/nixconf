{ pkgs, inputs, ... }: {
  environment.systemPackages = with inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}; [
    qemu
    quickemu
  ];
}
