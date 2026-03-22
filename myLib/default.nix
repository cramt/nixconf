{inputs}: let
  myLib = (import ./default.nix) {inherit inputs;};
  outputs = inputs.self.outputs;
in rec {
  # ================================================================ #
  # =                            My Lib                            = #
  # ================================================================ #

  # ======================= Package Helpers ======================== #

  pkgsFor = sys: inputs.nixpkgs.legacyPackages.${sys};

  # ========================== Buildables ========================== #

  mkSystemConfig = config: {
    specialArgs = {
      inherit inputs outputs myLib;
    };
    # outputs.nixosModules has "default" plus flat entries like "features.bluetooth",
    # "bundles.general", "services.caddy" — each already a valid NixOS module
    # (flake-parts wraps each entry with {_class, _file, imports=[v]}).
    modules =
      [
        config
        outputs.nixosModules.default
        inputs.opnix.nixosModules.default
      ]
      ++ builtins.attrValues (builtins.removeAttrs outputs.nixosModules ["default"]);
  };

  mkSystem = config: inputs.nixpkgs.lib.nixosSystem (mkSystemConfig config);

  mkHome = sys: config:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor sys;
      extraSpecialArgs = {
        inherit inputs;
      };
      modules =
        [
          config
          outputs.homeManagerModules.default
          inputs.nix-index-database.homeModules.nix-index
        ]
        ++ builtins.attrValues outputs.homeManagerModules.features
        ++ builtins.attrValues outputs.homeManagerModules.bundles;
    };

  # =========================== Helpers ============================ #

  filesIn = dir: (map (fname: dir + "/${fname}")
    (builtins.attrNames (builtins.readDir dir)));

  dirsIn = dir:
    inputs.nixpkgs.lib.filterAttrs (name: value: value == "directory")
    (builtins.readDir dir);

  fileNameOf = path: (builtins.head (builtins.split "\\." (baseNameOf path)));
}
