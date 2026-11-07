# Windows installs, built by defenestrate. A top-level output rather than
# packages: CI prebuilds every package, and these need the stock Windows ISO,
# which only exists in a store someone added it to by hand.
{inputs, ...}: {
  flake.windows.saturn = inputs.defenestrate.lib.x86_64-linux.mkDistro [
    "${inputs.defenestrate}/configs/default.nix"
    ../../hosts/saturn/windows.nix
  ];
}
