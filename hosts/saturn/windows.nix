# saturn's Windows, installed onto the 970 EVO from the ISO this builds:
#   nix build .#windows.saturn.build.iso
# Options are defenestrate's (github:cramt/defenestrate, nix/module.nix); the
# distro-wide debloat comes from its configs/default.nix.
{...}: {
  user.name = "cramt";
  # Not "saturn": the Linux side already answers to that on the LAN.
  computerName = "saturn-windows";
  inputLocale = "0406:00000406"; # Danish, like the Linux side
  timeZone = "Romance Standard Time"; # Europe/Copenhagen
  # disk stays at the default, setup's interactive picker. Its DiskID
  # numbering isn't stable across boots, so wiping one by number could hit
  # the Linux SSD.
}
