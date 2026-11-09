# Windows installs, built by defenestrate. A top-level output rather than
# packages: CI prebuilds every package, and these need the 9 GB stock Windows
# ISO and a KVM install run, nothing CI should do on every push.
{
  inputs,
  self,
  lib,
  ...
}: let
  # What WSL mounts on Windows is what saturn's Linux mounts at boot. By the
  # btrfs label rather than the partlabel the Linux side uses: inside WSL
  # there's no udev, so no /dev/disk/by-partlabel, but busybox findfs knows
  # labels. x-* options are systemd's, not the kernel's.
  linuxMounts = let
    fileSystems = self.nixosConfigurations.saturn.config.fileSystems;
  in
    map (target: {
      device = "LABEL=nvme-pool";
      inherit target;
      inherit (fileSystems.${target}) fsType;
      options = lib.filter (o: !lib.hasPrefix "x-" o) fileSystems.${target}.options;
    }) ["/" "/nix" "/home"];
in {
  # defenestrate layers its distro defaults (configs/default.toml) itself.
  flake.windows.saturn = inputs.defenestrate.lib.x86_64-linux.mkDistro [
    ../../hosts/saturn/windows.nix
    {wsl.linux.mounts = linuxMounts;}
  ];
}
