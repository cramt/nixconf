# saturn's Windows. Flashes a sandbox-built image onto the 970 EVO, no boot media:
#   nix run .#windows.saturn.build.install
# (.#windows.saturn.build.iso is the same install as a USB stick ISO.)
# Options are defenestrate's (github:cramt/defenestrate, nix/module.nix); the
# distro-wide debloat comes from its configs/default.nix.
{...}: {
  user.name = "cramt";
  # Not "saturn": the Linux side already answers to that on the LAN.
  computerName = "saturn-windows";
  inputLocale = "0406:00000406"; # Danish, like the Linux side
  timeZone = "Romance Standard Time"; # Europe/Copenhagen
  installTarget = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E";
  # disk stays at the default, setup's interactive picker, for the USB ISO.
  # Its DiskID numbering isn't stable across boots, so wiping one by number
  # could hit the Linux SSD. build.install doesn't have that problem: the image
  # is set up in a sandboxed VM whose only disk is a scratch file.
}
