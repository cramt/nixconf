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

  # While home.nix sets a defenestrate test plan, the shell opens Claude Code
  # on it at logon, through start-tests.ps1 (claude-code.windows in
  # modules/hm-features/claude-code.nix), which the logon task copies over
  # after the shell has started; so the line waits for it.
  testPlan = self.nixosConfigurations.saturn.config.home-manager.users.cramt.myHomeManager.claude-code.windows.testPlan;
  claudeAutostart = lib.concatStrings [
    "powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -Command \""
    "while (-not (Test-Path ~/.claude/start-tests.ps1)) { Start-Sleep 5 }; & ~/.claude/start-tests.ps1\""
  ];
in {
  # defenestrate layers its distro defaults (configs/default.toml) itself.
  flake.windows.saturn = inputs.defenestrate.lib.x86_64-linux.mkDistro [
    ../../hosts/saturn/windows.nix
    ../../hosts/saturn/windows-pins.toml
    {wsl.linux.mounts = linuxMounts;}
    # Light or dark like the Linux side, from its one stylix declaration.
    {cosmic.mode.is_dark = self.nixosConfigurations.saturn.config.stylix.polarity != "light";}
    {autostart = lib.optional (testPlan != null) claudeAutostart;}
  ];
}
