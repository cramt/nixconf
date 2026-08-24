{ lib, config, inputs, ... }:
let
  hostSystem = name:
    inputs.self.nixosConfigurations.${name}.config.nixpkgs.hostPlatform.system;

  # deploy-rs's own lib builds the activation binary from its flake's source.
  # Swap in nixpkgs' prebuilt deploy-rs while keeping deploy-rs's lib functions,
  # otherwise eros's aarch64 wrapper compiles Rust under binfmt on every deploy.
  # Documented pattern: https://github.com/serokell/deploy-rs#overall-usage
  deployLibFor = system:
    let
      basePkgs = import inputs.nixpkgs { inherit system; };
    in
    (import inputs.nixpkgs {
      inherit system;
      overlays = [
        inputs.deploy-rs.overlays.default
        (final: prev: {
          deploy-rs = {
            inherit (basePkgs) deploy-rs;
            inherit (prev.deploy-rs) lib;
          };
        })
      ];
    }).deploy-rs.lib;

  # The activation wrapper runs on the *target*, so index deploy-rs's lib by the
  # host's own platform rather than the deploying machine's — eros needs
  # aarch64. One lib per distinct platform, not per host: instantiating nixpkgs
  # is expensive and saturn/mars/luna/ganymede all share x86_64-linux.
  deployLibs = lib.genAttrs
    (lib.unique (map hostSystem (builtins.attrNames config.nixosHosts)))
    deployLibFor;

  # Structure-only copy of the deploy tree; see the comment on `checks` below.
  schemaOnlyDeploy = inputs.self.deploy // {
    nodes = lib.mapAttrs
      (_: node: node // {
        profiles = lib.mapAttrs
          (_: profile: profile // { path = "<activation profile>"; })
          node.profiles;
      })
      inputs.self.deploy.nodes;
  };
in
{
  flake.deploy = {
    sshUser = "root";
    user = "root";
    # luna starts a lot of heavy units in one go (postgres, jellyfin, the *arrs,
    # llama-cpp's model loader), and deploy-rs' 240s/30s defaults are sized for
    # a machine that activates in seconds. Too short and magic rollback reverts
    # a perfectly good deploy just for being slow.
    activationTimeout = 900;
    confirmTimeout = 120;

    nodes = lib.mapAttrs (name: host: {
      hostname = host.address;

      # Never build on the target — eros is a 2GB Pi that falls over on eval
      # alone. Whoever runs `just deploy` builds, and the closure is copied.
      remoteBuild = false;

      profiles.system.path =
        (deployLibs.${hostSystem name}).activate.nixos
          inputs.self.nixosConfigurations.${name};
    }) config.nixosHosts;
  };

  # Schema validation for the above. Only for platforms we actually deploy to,
  # so `nix flake check` on darwin doesn't instantiate nixpkgs for nothing.
  #
  # The check validates the *shape* of the deploy attrset, but rendering that
  # attrset to JSON makes every node's activation profile a build-time
  # dependency of the check — and deploy-rs runs `nix flake check` before every
  # deploy, so `just deploy luna` ended up building the whole fleet, eros's
  # aarch64 closure included, to validate a JSON document. The schema types
  # `path` as a plain string, so feeding it a placeholder keeps the structural
  # validation honest and costs nothing.
  #
  # deployChecks also ships `deploy-activate`, which is dropped: it realises
  # every node's activation profile by design, which is the same full-fleet
  # build. `just deploy` does that build against the hosts it's actually
  # deploying to, so the check buys nothing for its cost. Subtractive so
  # upstream's future checks still run by default.
  perSystem = { system, ... }: {
    checks = lib.optionalAttrs (deployLibs ? ${system})
      (builtins.removeAttrs
        (deployLibs.${system}.deployChecks schemaOnlyDeploy)
        [ "deploy-activate" ]);
  };
}
