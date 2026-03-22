{inputs}: let
  outputs = inputs.self.outputs;
in {
  mkSystem = config: inputs.nixpkgs.lib.nixosSystem {
    specialArgs = {
      inherit inputs outputs;
    };
    modules =
      [
        config
        outputs.nixosModules.default
        inputs.opnix.nixosModules.default
      ]
      ++ builtins.attrValues (builtins.removeAttrs outputs.nixosModules ["default"]);
  };
}
