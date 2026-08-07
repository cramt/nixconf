{inputs}: let
  outputs = inputs.self.outputs;
in {
  mkSystem = { name, config, nixpkgs ? inputs.nixpkgs, ... }: nixpkgs.lib.nixosSystem {
    specialArgs = {
      inherit inputs outputs;
      # The host's directory, so modules can derive per-host paths (e.g.
      # bundles.users pointing at hosts/<name>/home.nix) instead of every host
      # repeating them. A specialArg rather than config.networking.hostName so
      # it's usable from option defaults without risking infinite recursion.
      hostDir = builtins.dirOf config;
    };
    modules =
      [
        config
        # The folder name *is* the hostname; mkDefault so a host can override.
        { networking.hostName = nixpkgs.lib.mkDefault name; }
        outputs.nixosModules.default
        inputs.opnix.nixosModules.default
      ]
      ++ builtins.attrValues (builtins.removeAttrs outputs.nixosModules ["default"]);
  };
}
