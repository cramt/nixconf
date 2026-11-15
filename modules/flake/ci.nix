# The CI build plan as data: `nix eval --json .#ci` is every leg build.yml
# runs, stage by stage, each with the runner it builds on. Nothing about what CI
# builds lives in the workflow.
#
#   packages     flake packages, prebuilt into cachix before the hosts
#   hosts        one deploy-rs activation profile each (toplevel + activate-rs)
#   after_hosts  packages that wrap a host's closure (SD images, flashers), so
#                they substitute it instead of compiling it a second time
#
# A package picks its stage and runner through meta.ci (see the afterHosts /
# noCi / ci helpers in packages.nix); a host picks its runner with ciRunner in
# host.nix. Both default from the build system via myLib/ci-runners.nix.
{ lib, config, inputs, ... }:
let
  runners = import ../../myLib/ci-runners.nix;
  stages = [ "prebuild" "after-hosts" "skip" ];

  runnerFor = system: runners.${system};

  # meta isn't type-checked, so a typo'd stage or runner would otherwise just
  # put the package somewhere unexpected.
  checkPackageCi = name: ci:
    let
      unknown = builtins.attrNames (removeAttrs ci [ "stage" "runner" ]);
      stage = ci.stage or "prebuild";
      runner = ci.runner or null;
    in
    if unknown != [ ] then
      throw "packages.${name}: unknown meta.ci attribute(s) ${lib.concatStringsSep ", " unknown} (stage, runner)"
    else if !(lib.elem stage stages) then
      throw "packages.${name}: unknown meta.ci.stage \"${stage}\" (${lib.concatStringsSep ", " stages})"
    else if runner != null && !(lib.elem runner (lib.attrValues runners)) then
      throw "packages.${name}: unknown meta.ci.runner \"${runner}\" (${lib.concatStringsSep ", " (lib.attrValues runners)})"
    else { inherit stage runner; };

  # Only what's buildable on that system: meta.available drops unsupported
  # platforms (arm-only steamlink on x86) and unfree licenses (steamlink), which
  # would otherwise fail their leg at eval time.
  packageLegs = lib.concatLists (lib.mapAttrsToList (system: packages:
    lib.concatLists (lib.mapAttrsToList (name: drv:
      let
        available = builtins.tryEval (drv.meta.available or true);
        ci = checkPackageCi name (drv.meta.ci or { });
      in
      lib.optional (available.success && available.value) {
        package = name;
        inherit system;
        inherit (ci) stage;
        runner = if ci.runner != null then ci.runner else runnerFor system;
      }) packages))
    (lib.filterAttrs (system: _: runners ? ${system}) inputs.self.packages));

  inStage = stage: {
    include = map (leg: removeAttrs leg [ "stage" ])
      (lib.filter (leg: leg.stage == stage) packageLegs);
  };

  # A cross-built host (venus, armv7l) builds on its build platform's runner.
  hostLeg = name: host:
    let system = inputs.self.nixosConfigurations.${name}.pkgs.stdenv.buildPlatform.system;
    in {
      host = name;
      runner =
        if host.ciRunner != null then host.ciRunner
        else runners.${system} or (throw "hosts/${name}: no CI runner for ${system}; add one to myLib/ci-runners.nix or set ciRunner in host.nix");
    };
in
{
  flake.ci = {
    packages = inStage "prebuild";
    hosts.include = lib.mapAttrsToList hostLeg config.nixosHosts;
    after_hosts = inStage "after-hosts";
  };
}
