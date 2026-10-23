#!/usr/bin/env bash
# Emits two GitHub Actions matrices: `matrix` (one entry per flake package, per
# Linux system) so each package is prebuilt on its own runner and pushed to
# cachix, and `hosts` (one entry per nixosConfiguration) for the toplevel builds. The set of
# things CI builds is exactly `nix flake show`'s packages — drop a folder into
# packages/ (or add an output to modules/flake/packages.nix) and it joins.
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

# Skipped: trivial wrappers around a cross-platform artifact. flash-eros (x86)
# only substitutes the aarch64 eros image — it can't build it, and its own
# eros-img leg races it in the same wave, so it fails whenever the image drv
# changed (e.g. every update PR). The wrapper builds in seconds locally once
# eros-img is cached, so prebuilding it adds nothing.
#
# mercury-img-cross: cross-compiling the whole mercury system from x86 doesn't
# work yet, and it isn't what gets flashed (that's the natively-built
# mercury-img on the ARM runner). stylix's palette generator and btop's
# wrapper are fixed; home-manager still builds its own native aarch64 pkgs
# (see the comment on mercury-img-cross). saturn never sees any of this because
# binfmt lets it execute aarch64 builds anyway. Un-skip once that's resolved.
skip='["flash-eros", "mercury-img-cross"]'

include='[]'
for system in "${!runners[@]}"; do
  names=$(nix eval --json ".#packages.${system}" --apply "$filter")
  include=$(jq -cn \
    --argjson acc "$include" \
    --argjson names "$names" \
    --argjson skip "$skip" \
    --arg system "$system" \
    --arg runner "${runners[$system]}" \
    '$acc + [ $names[] | select(. as $n | $skip | index($n) | not) | { package: ., system: $system, runner: $runner } ]')
done

echo "matrix={\"include\":${include}}" >>"$GITHUB_OUTPUT"
echo "Generated package matrix:"
jq <<<"{\"include\":${include}}"

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
