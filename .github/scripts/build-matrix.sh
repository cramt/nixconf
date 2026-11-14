#!/usr/bin/env bash
# Emits three GitHub Actions matrices, one per CI stage, each waiting on the one
# before it:
#   matrix       flake packages, prebuilt on their own runners into cachix
#   hosts        one leg per nixosConfiguration toplevel
#   after_hosts  packages that wrap a host's closure (SD images, flashers), so
#                they substitute it instead of compiling it a second time
# A package's stage is its meta.ciStage (set in modules/flake/packages.nix):
# unset for `matrix`, "after-hosts", or "skip" to keep it out of CI. Anything
# else fails here. The set of things CI builds is exactly `nix flake show`'s
# packages: drop a folder into packages/ (or add an output to
# modules/flake/packages.nix) and it joins.
set -euo pipefail

# system -> runner label
declare -A runners=(
  [x86_64-linux]=ubuntu-latest
  [aarch64-linux]=ubuntu-24.04-arm
)

# name -> stage, for the packages actually buildable on this system:
# meta.available drops unsupported platforms (e.g. arm-only steamlink on x86)
# and unfree licenses (e.g. steamlink), which would otherwise fail the build job
# at eval time.
stages='set: builtins.listToAttrs (builtins.concatMap (n:
  let
    p = set.${n};
    avail = builtins.tryEval (p.meta.available or true);
    stage = p.meta.ciStage or "prebuild";
  in
    if !(avail.success && avail.value) then [ ]
    else if builtins.elem stage [ "prebuild" "after-hosts" "skip" ] then [ { name = n; value = stage; } ]
    else throw "packages.${n}: unknown meta.ciStage \"${stage}\" (prebuild, after-hosts or skip)"
) (builtins.attrNames set))'

prebuild='[]'
after_hosts='[]'
for system in "${!runners[@]}"; do
  named=$(nix eval --json ".#packages.${system}" --apply "$stages")
  pick() {
    jq -cn --argjson acc "$1" --argjson named "$named" --arg stage "$2" \
      --arg system "$system" --arg runner "${runners[$system]}" \
      '$acc + [ $named | to_entries[] | select(.value == $stage) | { package: .key, system: $system, runner: $runner } ]'
  }
  prebuild=$(pick "$prebuild" prebuild)
  after_hosts=$(pick "$after_hosts" after-hosts)
done

echo "matrix={\"include\":${prebuild}}" >>"$GITHUB_OUTPUT"
echo "Generated package matrix:"
jq <<<"{\"include\":${prebuild}}"

echo "after_hosts={\"include\":${after_hosts}}" >>"$GITHUB_OUTPUT"
echo "Generated after-hosts matrix:"
jq <<<"{\"include\":${after_hosts}}"

# One leg per nixosConfiguration, on a runner native to the platform that builds
# it: its own system, or x86 for a cross-built host like venus (armv7l). hosts.nix
# discovers hosts from hosts/, so a new host joins CI with no edit here.
runners_json=$(for s in "${!runners[@]}"; do echo "$s ${runners[$s]}"; done |
  jq -Rn '[inputs | split(" ") | {(.[0]): .[1]}] | add')
hosts=$(nix eval --json .#nixosConfigurations \
  --apply 'cs: builtins.mapAttrs (_: c: c.pkgs.stdenv.buildPlatform.system) cs' |
  jq -c --argjson runners "$runners_json" \
    '[to_entries[] | { host: .key, runner: ($runners[.value] // error("no runner for \(.key) (\(.value))")) }]')

echo "hosts={\"include\":${hosts}}" >>"$GITHUB_OUTPUT"
echo "Generated host matrix:"
jq <<<"{\"include\":${hosts}}"
