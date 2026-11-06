{inputs, ...}: {
  imports = [inputs.flake-parts.flakeModules.touchup];

  # We define no formatter, but flake-parts' "is perSystem.formatter always
  # null?" probe can't prove that for this flake, so it emits a
  # formatter.<system> that throws and breaks `nix flake show`/`check`.
  # https://github.com/hercules-ci/flake-parts/issues/288
  # Remove once nix flake show/check accept null outputs and flake-parts stops guessing.
  touchup.attr.formatter.enable = false;
}
