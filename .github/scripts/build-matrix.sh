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

# Skipped: trivial wrappers around a cross-platform artifact. flash-eros (x86)
# only substitutes the aarch64 eros image — it can't build it, and its own
# eros-img leg races it in the same wave, so it fails whenever the image drv
# changed (e.g. every update PR). The wrapper builds in seconds locally once
# eros-img is cached, so prebuilding it adds nothing.
#
# mercury-img-cross needs to *run* an aarch64 binary during evaluation: stylix's
# paletteGenerator is indexed by hostPlatform, not buildPlatform, so a cross
# build hands the x86 builder an aarch64 executable and IFD dies with "Exec
# format error". The option is internal + readOnly, so it can't be overridden
# from our config. saturn runs it fine (binfmt + extra-platforms), which is the
# only place it's meant to run — it's a local-iteration convenience that
# deliberately shares no store paths with mercury-img, so CI prebuilding it
# caches nothing anything else substitutes from. Drop this once stylix indexes
# the generator by buildPlatform (nix-community/stylix flake/modules.nix:13).
skip='["flash-eros","mercury-img-cross"]'

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
echo "Generated matrix:"
jq <<<"{\"include\":${include}}"
