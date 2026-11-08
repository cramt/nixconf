# Where op-secrets (modules/security/secrets.nix) reads its token and renders
# secrets. A plain file so home-manager modules, which can't see the NixOS
# config, use the same paths.
{
  # Still named after opnix: every host and flash image already carries it at
  # this path, and moving it is a manual step on each.
  tokenFile = "/etc/opnix-token";
  # Persistent, not /run: a host that boots offline (eros and ganymede need a
  # secret to get on the wifi at all) keeps the last render.
  dir = "/var/lib/op-secrets";
  group = "onepassword-secrets";
}
