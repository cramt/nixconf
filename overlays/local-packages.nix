# Every packages/<name>/default.nix becomes pkgs.<name>, the way every
# hosts/<name>/ becomes a host: dropping the folder in is the whole
# registration. modules/flake/packages.nix exports the same names as flake
# packages, so CI prebuilds them and `nix-update --flake <name>` finds them.
#
# A folder named after a nixpkgs attribute shadows it for every consumer
# (agent-browser, cockatrice: nixpkgs lags the versions we track), so
# home-manager's buildEnv never sees two copies.
let
  entries = builtins.readDir ../packages;
  names = builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);
in {
  inherit names;
  overlay = final: _prev:
    builtins.listToAttrs (map (name: {
        inherit name;
        value = final.callPackage ../packages/${name} {};
      })
      names);
}
