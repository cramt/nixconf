# Phones: rooted Android managed by Nixup (inputs.nixup). Not NixOS, so they
# can't live in hosts/ (every directory there becomes a nixosConfiguration);
# phones/ is discovered the same way instead. Each phones/<name>/configuration.nix
# is a Nixup module, evaluated with every nixupModules.* entry, the way mkSystem
# hands a host every nixosModules.* entry.
#
# Applied by `just phone <name>`: nixup-rebuild evaluates it here and pushes the
# profile to the phone over adb or ssh. The phone itself fetches the store paths.
{ lib, inputs, config, ... }:
let
  phonesDir = ../../phones;
  phoneNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir phonesDir)
  );
in
{
  # Freeform flake outputs don't merge per key across files, so the
  # accumulator is typed, like hmModules (hm-modules.nix).
  options.nixupModules = lib.mkOption {
    type = lib.types.attrsOf lib.types.deferredModule;
    default = { };
    description = "Nixup modules every phone imports, by name.";
  };

  # nixup-rebuild, nixup-config, nixup-play-login, at the rev flake.lock pins.
  # `nix run --inputs-from . nixup` would re-lock Nixup's own nixpkgs instead.
  config.perSystem = { system, ... }: {
    apps = lib.filterAttrs (name: _: name != "default") (inputs.nixup.apps.${system} or { });

    # Nixup's toplevel is profile data, not a derivation, so nothing builds it
    # as a whole. Writing it to the store does: the store paths in the JSON are
    # its references, so its closure is exactly what the phone fetches, and
    # CI's build of `phone-<name>` puts all of it in the hestia cache.
    packages = lib.mapAttrs' (name: phone:
      let pkgs = phone._module.args.pkgs;
      in lib.nameValuePair "phone-${name}"
        (pkgs.writeText "nixup-${name}-profile.json"
          (builtins.toJSON phone.config.system.build.toplevel)))
      (lib.filterAttrs (_: phone: phone._module.args.pkgs.stdenv.hostPlatform.system == system)
        config.flake.nixupConfigurations);
  };

  config.flake = {
    nixupModules = config.nixupModules;

    nixupConfigurations = lib.genAttrs phoneNames (name:
      inputs.nixup.lib.nixupSystem {
        modules = lib.attrValues config.nixupModules ++ [
          (phonesDir + "/${name}/configuration.nix")
          # Like hosts: the folder name is the device and tailnet name.
          { networking.hostName = lib.mkDefault name; }
        ];
        specialArgs = { inherit inputs; };
      });
  };
}
