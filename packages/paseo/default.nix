# Paseo — self-hosted daemon/CLI for AI coding agents (getpaseo/paseo).
#
# Not in nixpkgs yet: no `paseo` attribute and no packaging PR as of 2026-07.
# Upstream ships its own derivation at nix/package.nix, so instead of vendoring
# a copy that drifts, we fetch the tagged source and callPackage upstream's file
# verbatim. This is `packages.default` from their flake (the daemon + `paseo`
# CLI); the Electron desktop app lives in nix/desktop-package.nix if we want it.
#
# TODO: delete this dir + the overlay entry in overlays/default.nix once paseo
#   lands in nixpkgs. Track: https://github.com/NixOS/nixpkgs (search `paseo`).
#   Upstream derivation: https://github.com/getpaseo/paseo/blob/main/nix/package.nix
{ callPackage, fetchFromGitHub }:
let
  src = fetchFromGitHub {
    owner = "getpaseo";
    repo = "paseo";
    tag = "v0.2.0";
    hash = "sha256-fkSjsoGQryMkUic+pbj6QXjCNn5Klh3ed/BKcnllkYE=";
  };
in
# package.nix reads ../package.json (version) and ./npm-deps.hash relative to
# nix/, both of which resolve inside the fetched src. If our nixpkgs pin yields
# a different fetchNpmDeps FOD hash than upstream's checked-in one, override with
# `.override { npmDepsHash = "sha256-..."; }` (the arg is destructured out of
# buildNpmPackage, so overrideAttrs can't reach it).
callPackage "${src}/nix/package.nix" { }
