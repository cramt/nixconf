# GitHub Actions runner per build system. The values are also the only runner
# labels a package's meta.ci.runner or a host's ciRunner may name. A system
# missing here (the darwins in modules/flake/systems.nix) is never built by CI.
{
  x86_64-linux = "ubuntu-latest";
  aarch64-linux = "ubuntu-24.04-arm";
}
