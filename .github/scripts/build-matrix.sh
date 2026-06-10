#!/usr/bin/env bash
# Emits a GitHub Actions matrix (one entry per flake package, per Linux system)
# so each package is prebuilt on its own runner and pushed to cachix. The set of
# things CI builds is exactly `nix flake show`'s packages — add a package to
# modules/flake/packages.nix and it joins the build automatically.
set -euo pipefail

# system -> runner label
declare -A runners=(
  [x86_64-linux]=ubuntu-latest
  [aarch64-linux]=ubuntu-24.04-arm
)

# Only the packages actually buildable on this system: meta.available drops
# unsupported platforms (e.g. arm-only steamlink on x86) and unfree licenses
# (e.g. steamlink), which would otherwise fail the build job at eval time.
filter='set: builtins.filter (n: let r = builtins.tryEval (set.${n}.meta.available or true); in r.success && r.value) (builtins.attrNames set)'

include='[]'
for system in "${!runners[@]}"; do
  names=$(nix eval --json ".#packages.${system}" --apply "$filter")
  include=$(jq -cn \
    --argjson acc "$include" \
    --argjson names "$names" \
    --arg system "$system" \
    --arg runner "${runners[$system]}" \
    '$acc + [ $names[] | { package: ., system: $system, runner: $runner } ]')
done

echo "matrix={\"include\":${include}}" >>"$GITHUB_OUTPUT"
echo "Generated matrix:"
jq <<<"{\"include\":${include}}"
