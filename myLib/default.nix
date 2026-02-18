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
        inherit inputs myLib outputs;
      };
      # outputs.homeManagerModules is freeform (flake-parts passes it raw),
      # so features/bundles are raw attrsets of module functions.
      modules =
        [
          config
          outputs.homeManagerModules.default
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

  # ========================== Extenders =========================== #

  # Evaluates nixos/home-manager module and extends it's options / config
  extendModule = {path, ...} @ args: {pkgs, ...} @ margs: let
    eval =
      if (builtins.isString path) || (builtins.isPath path)
      then import path margs
      else path margs;
    evalNoImports = builtins.removeAttrs eval ["imports" "options"];

    extra =
      if (builtins.hasAttr "extraOptions" args) || (builtins.hasAttr "extraConfig" args)
      then [
        ({...}: {
          options = args.extraOptions or {};
          config = args.extraConfig or {};
        })
      ]
      else [];
  in {
    imports =
      (eval.imports or [])
      ++ extra;

    options =
      if builtins.hasAttr "optionsExtension" args
      then (args.optionsExtension (eval.options or {}))
      else (eval.options or {});

    config =
      if builtins.hasAttr "configExtension" args
      then (args.configExtension (eval.config or evalNoImports))
      else (eval.config or evalNoImports);
  };

  # Applies extendModules to all modules
  # modules can be defined in the same way
  # as regular imports, or taken from "filesIn"
  extendModules = extension: modules:
    map
    (f: let
      name = fileNameOf f;
    in (extendModule ((extension name) // {path = f;})))
    modules;

  # Wraps a module at `path` with a self-contained enable option.
  # optionAttrPath: e.g. ["myNixOS" "bluetooth"] or ["myNixOS" "bundles" "general"]
  # enableDescription: string passed to lib.mkEnableOption
  # path: file path or module function
  mkEnabledModule = optionAttrPath: enableDescription: path:
    {config, lib, pkgs, ...} @ margs: let
      mod =
        if (builtins.isString path) || (builtins.isPath path)
        then import path margs
        else path margs;
      modNoImports = builtins.removeAttrs mod ["imports" "options"];
      fullOptionPath = optionAttrPath ++ ["enable"];
      isEnabled = lib.attrByPath fullOptionPath false config;
      enableOption = lib.mkEnableOption enableDescription;
      ownEnableOptions = lib.foldr (a: b: {"${a}" = b;}) enableOption fullOptionPath;
    in {
      imports = mod.imports or [];
      options = lib.recursiveUpdate (mod.options or {}) ownEnableOptions;
      config = lib.mkIf isEnabled (mod.config or modNoImports);
    };

}
