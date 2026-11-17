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
  # on it at logon. It waits for the logon task to copy the plan and the pool
  # key over from Linux, which can land after the shell starts. The prompt
  # stays free of quotes: it rides inside PowerShell's -Command string.
  testPlan = self.nixosConfigurations.saturn.config.home-manager.users.cramt.myHomeManager.claude-code.windows.testPlan;
  testPrompt = lib.concatStringsSep " " [
    "Alex just booted into this Windows to test defenestrate and is watching this console."
    "Work through ~/.claude/defenestrate-tests.md, asking her here for anything only a person at the screen can check."
    "When the report is written, tell her where it is, give her a minute to read it, then reboot to Linux with: schtasks /run /tn defenestrate-reboot-to-linux"
  ];
  claudeAutostart = lib.concatStrings [
    "powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -Command \""
    "Write-Host 'Waiting for the logon task to copy Claude config from Linux (log: %LOCALAPPDATA%/defenestrate/wsl.log)'; "
    "while (-not ((Test-Path ~/.claude/pool-key) -and (Test-Path ~/.claude/defenestrate-tests.md))) { Start-Sleep 2 }; "
    "claude --dangerously-skip-permissions '${testPrompt}'\""
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
