{ lib, config, inputs, ... }:
let
  platformsOf = name: let
    inherit (inputs.self.nixosConfigurations.${name}.config.nixpkgs) buildPlatform hostPlatform;
  in {
    localSystem = buildPlatform.system;
    crossSystem = hostPlatform.system;
  };
  hostSystem = name: (platformsOf name).crossSystem;

  # deploy-rs's own lib builds the activation binary from its flake's source.
  # Swap in nixpkgs' prebuilt deploy-rs while keeping deploy-rs's lib functions,
  # otherwise eros's aarch64 wrapper compiles Rust under binfmt on every deploy.
  # Documented pattern: https://github.com/serokell/deploy-rs#overall-usage
  #
  # Imported with the host's own build/host pair, so a cross-built host (venus)
  # gets a cross-compiled activate-rs instead of one nothing here can build.
  # Native hosts pass the same system twice, which nixpkgs treats as native.
  deployLibFor = platforms:
    let
      basePkgs = import inputs.nixpkgs platforms;
    in
    (import inputs.nixpkgs (platforms // {
      overlays = [
        inputs.deploy-rs.overlays.default
        (final: prev: {
          deploy-rs = {
            inherit (basePkgs) deploy-rs;
            inherit (prev.deploy-rs) lib;
          };
        })
      ];
    })).deploy-rs.lib;

  # The activation wrapper runs on the *target*, so index deploy-rs's lib by the
  # host's own platform rather than the deploying machine's — eros needs
  # aarch64. One lib per distinct platform, not per host: instantiating nixpkgs
  # is expensive and saturn/mars/luna/ganymede all share x86_64-linux. Keyed by
  # host system alone, which assumes no two hosts share a target but build it
  # from different platforms.
  deployLibs = lib.listToAttrs (map
    (name: lib.nameValuePair (hostSystem name) (deployLibFor (platformsOf name)))
    (builtins.attrNames config.nixosHosts));

  nodeFor = name: {
    # Never build on the target — eros is a 2GB Pi that falls over on eval
    # alone. Whoever runs `just deploy` builds, and the closure is copied.
    remoteBuild = false;

    profiles.system.path =
      (deployLibs.${hostSystem name}).activate.nixos
        inputs.self.nixosConfigurations.${name};
  };

  lanNodes = lib.mapAttrs
    (name: host: nodeFor name // { hostname = host.address; })
    config.nixosHosts;

  # The same host and profile again, reached through its port forward. The
  # `-remote` suffix is what the Justfile uses to leave these out of a bare
  # `just deploy`: from the LAN, hairpin NAT means both would answer.
  wanNodes = lib.mapAttrs'
    (name: host: lib.nameValuePair "${name}-remote" (nodeFor name // {
      hostname = host.wan.address;
      sshOpts = [ "-p" (toString host.wan.port) ];
    }))
    (lib.filterAttrs (_: host: host.wan != null) config.nixosHosts);

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
    # luna starts a lot of heavy units in one go (postgres, jellyfin,
    # the *arrs), and deploy-rs' 240s/30s defaults are sized for
    # a machine that activates in seconds. Too short and magic rollback reverts
    # a perfectly good deploy just for being slow.
    activationTimeout = 900;
    confirmTimeout = 120;

    nodes = lanNodes // wanNodes;
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
