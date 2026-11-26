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
  # after the shell has started; so the line waits for this logon's copies
  # (linux-files.txt, written after them, newer than the boot), not the
  # last boot's, which once ran a stale script on a stale plan.
  testPlan = self.nixosConfigurations.saturn.config.home-manager.users.cramt.myHomeManager.claude-code.windows.testPlan;
  claudeAutostart = lib.concatStrings [
    "powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -Command \""
    "$f = Join-Path $env:LOCALAPPDATA 'defenestrate/linux-files.txt'; $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime; "
    "while (-not ((Test-Path $f) -and (Get-Item $f).LastWriteTime -gt $boot)) { Start-Sleep 5 }; & ~/.claude/start-tests.ps1\""
  ];

  # Firefox (winget's, in hosts/saturn/windows.nix) gets Zen's extensions as
  # enterprise policy, from the same list (myLib/browser-extensions.nix).
  # Policy goes in the registry rather than distribution\policies.json next
  # to firefox.exe: winget only installs Firefox at the first real boot,
  # long after the image is built, and defenestrate has no way to drop a
  # file into Program Files after that; HKLM\SOFTWARE is written at setup
  # and Firefox reads it whenever it shows up. A JSON-valued policy is
  # REG_MULTI_SZ holding the JSON (Mozilla's policy-templates, "Windows
  # (GPO)"). Keyed by addon id, and the URL is by id too, which AMO resolves
  # the same as the slug (and rycee's ids come from AMO itself). AMO's
  # latest rather than nix's pin: the reason zen.nix pins (HM's symlinks
  # fighting the browser's own updates) doesn't exist here.
  # Zen's custom move-tab-to-new-window isn't here: it isn't on AMO, and
  # release Firefox installs only signed xpis, policy or not (unsigned needs
  # ESR, Developer Edition or Nightly). Shipping it would mean submitting it
  # to AMO as unlisted for signing, then pointing install_url at the signed
  # xpi (a wsl.linux.files copy and a file:/// URL).
  firefoxPolicies = let
    extensions = import ../../myLib/browser-extensions.nix self.nixosConfigurations.saturn.pkgs.nur.repos.rycee.firefox-addons;
  in {
    # zen.nix's DisableAppUpdate isn't mirrored: nothing else updates
    # Firefox on Windows.
    DisableTelemetry.dword = 1;
    ExtensionSettings.multiSz = [
      (builtins.toJSON (lib.listToAttrs (map (e: {
          name = e.addonId;
          value = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/${lib.escapeURL e.addonId}/latest.xpi";
          };
        })
        extensions)))
    ];
  };
in {
  # defenestrate layers its distro defaults (configs/default.toml) itself.
  flake.windows.saturn = inputs.defenestrate.lib.x86_64-linux.mkDistro [
    ../../hosts/saturn/windows.nix
    ../../hosts/saturn/windows-pins.toml
    {wsl.linux.mounts = linuxMounts;}
    # Light or dark like the Linux side, from its one stylix declaration.
    {cosmic.mode.is_dark = self.nixosConfigurations.saturn.config.stylix.polarity != "light";}
    # Pointer speed and key repeat from the attrset cosmic-comp's config is
    # made of (modules/hm-features/cosmic.nix); defenestrate converts them.
    {cosmic.compositor = self.nixosConfigurations.saturn.config.home-manager.users.cramt.myHomeManager.cosmic.input;}
    {autostart = lib.optional (testPlan != null) claudeAutostart;}
    {registry.software."Policies\\Mozilla\\Firefox" = firefoxPolicies;}
    # Windows' Firefox rides along across reflashes (flash keeps it in
    # ~/.local/state/dfnstrate/persist/saturn-windows); with nothing kept yet,
    # the new profile starts from Zen's cookies, logins and containers, read
    # from wherever zen.nix puts its profile. Zen has to be closed while
    # flashing: it holds its databases locked.
    {
      persist.firefox.seed.profile = let
        zen = self.nixosConfigurations.saturn.config.home-manager.users.cramt.programs.zen-browser;
      in "${zen.configPath}/${zen.profiles.default.path}";
    }
  ];
}
