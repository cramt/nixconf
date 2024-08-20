{ pkgs, inputs, ... }: {
  environment.systemPackages = with inputs.nixpkgs-stable.legacyPackages.${pkgs.system}; [
    qemu
    quickemu
  ];
}
