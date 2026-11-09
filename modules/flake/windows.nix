# Windows installs, built by defenestrate. A top-level output rather than
# packages: CI prebuilds every package, and these need the 9 GB stock Windows
# ISO and a KVM install run, nothing CI should do on every push.
{inputs, ...}: {
  # defenestrate layers its distro defaults (configs/default.toml) itself.
  flake.windows.saturn = inputs.defenestrate.lib.x86_64-linux.mkDistro [
    ../../hosts/saturn/windows.nix
  ];
}
