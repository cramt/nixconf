{inputs}: let
  outputs = inputs.self.outputs;

  # opnix builds itself from a fresh `import pkgs.path { system = hostPlatform; }`,
  # which drops crossSystem, so a cross-built host (venus) asks for a native
  # armv7l stdenv nothing here can build. Build it from the host's own pkgs.
  # No upstream issue yet (brizzbuzz/opnix); drop this once the module builds
  # from `pkgs` or takes a `package` option.
  opnixModule = let
    # Copied in explicitly: toFile below references it, and under lazy trees
    # (Determinate Nix, which CI installs) a flake input's source is never
    # materialised on its own, so the reference would point at a path that
    # isn't in the store ("path '...-source' is not valid").
    src = builtins.path { path = inputs.opnix; name = "source"; };
    upstream = builtins.readFile "${src}/nix/module.nix";
    # Exact text, indentation included, hence a plain string.
    native = "import pkgs.path {\n    system = pkgs.stdenv.hostPlatform.system;\n    overlays = [\n      (final: prev: {\n        opnix = import ./package.nix {pkgs = final;};\n      })\n    ];\n  }";
    fromHostPkgs = "{opnix = import ${src}/nix/package.nix {inherit pkgs;};}";
    patched = builtins.replaceStrings [native] [fromHostPkgs] upstream;
  in
    assert patched != upstream || throw "opnix's module.nix changed; re-check the cross patch in myLib/default.nix";
      builtins.toFile "opnix-module.nix" patched;
in {
  mkSystem = { name, config, nixpkgs ? inputs.nixpkgs, buildPool ? {}, ... }: nixpkgs.lib.nixosSystem {
    specialArgs = {
      inherit inputs outputs buildPool;
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
        opnixModule
      ]
      ++ builtins.attrValues (builtins.removeAttrs outputs.nixosModules ["default"]);
  };
}
