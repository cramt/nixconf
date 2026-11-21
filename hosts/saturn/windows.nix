# saturn's Windows. Flashes a sandbox-built image onto the 970 EVO, no boot media:
#   nix run .#windows.saturn.build.install
# (.#windows.saturn.build.iso is the same install as a USB stick ISO.)
# Keys are defenestrate's config (github:cramt/defenestrate, cli/src/config.rs);
# the distro-wide debloat comes from its configs/default.toml.
{...}: let
  # The same monitor and mode the Linux side has. defenestrate matches the
  # monitor by its EDID model name and serial, the last two words of the name
  # Linux compositors give it ("<make> <model> <serial>").
  displays = map (m: let
    words = builtins.filter builtins.isString (builtins.split " " m.name);
    n = builtins.length words;
  in {
    model = builtins.elemAt words (n - 2);
    serial = builtins.elemAt words (n - 1);
    inherit (m.res) width height;
    refresh = m.refresh_rate;
  }) (import ./monitors.nix);
in {
  inherit displays;
  user.name = "cramt";
  # Not "saturn": the Linux side already answers to that on the LAN.
  computerName = "saturn-windows";
  inputLocale = "0406:00000406"; # Danish, like the Linux side
  timeZone = "Romance Standard Time"; # Europe/Copenhagen
  installTarget = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E";
  # Linux boots Limine off the removable path (modules/security/secureboot.nix:
  # MSI drops OS-made entries when Secure Boot settings change), whose only
  # firmware entry is the one MSI makes itself, "UEFI OS". defenestrate's
  # auto pick skips the removable path on purpose (a USB stick boots it too),
  # so it's named here; "Reboot to Linux" found nothing without it
  # (2026-11-20). If the firmware ever adds a second "UEFI OS" (Windows'
  # disk's fallback), linux-first refuses to choose and says so in its log.
  linuxBootEntry.description = "UEFI OS";
  # winget IDs, installed by winget on the first real boot (whatever version
  # it has then). League last: its installer is the Riot Client, which then
  # downloads the game, so it's the slow one.
  # Git for Claude Code's Bash tool (it falls back to PowerShell without).
  apps = ["Mozilla.Firefox" "Discord.Discord" "Git.Git" "Anthropic.ClaudeCode" "RiotGames.LeagueOfLegends.EUW"];
  # No defaultApps: Firefox stays out of reach as the default browser. The
  # shell's way (open Settings at Firefox's page) can't work, because
  # Settings, like every UWP app, won't start without explorer as the shell
  # (0x80040900 after 45 s, 2026-11-20); Microsoft's way around that is
  # Shell Launcher v2, Enterprise/Education only. Open: live with Edge,
  # disable UCPD.sys and let Firefox set itself, or another edition.
  # Downloads pinned by hash (the GPU driver) live in windows-pins.toml,
  # which `dfnstrate pins` rewrites; see modules/flake/windows.nix.
  # The Linux install, reached through WSL (terminal programs only; its GUI
  # apps don't show under defenestrate's shell): the logon task attaches the 980 (by its GPT disk GUID, `lsblk -dno PTUUID`) and mounts
  # the pool; the mounts come from saturn's NixOS fileSystems, in
  # modules/flake/windows.nix. Start Menu > "Linux terminal" is the shell.
  wsl.linux = {
    user = "cramt";
    disks = ["fba1d9d1-1150-4352-9ef6-83f00f0f27e8"];
    # Copied into %USERPROFILE% at every logon, so Claude Code on Windows
    # goes through the same pool with the same instructions. Config from
    # claude-code.windows (modules/hm-features/claude-code.nix); the key is
    # op-secrets' render from Linux's last boot, so nothing secret is in the
    # image.
    files = let
      claude = "/home/cramt/.local/share/defenestrate/claude";
    in {
      ".claude/settings.json" = "${claude}/settings.json";
      ".claude/CLAUDE.md" = "${claude}/CLAUDE.md";
      ".claude/pool-key.ps1" = "${claude}/pool-key.ps1";
      # Only there while home.nix sets claude-code.windows.testPlan.
      ".claude/defenestrate-tests.md" = "${claude}/defenestrate-tests.md";
      ".claude/start-tests.ps1" = "${claude}/start-tests.ps1";
      ".claude/hand-back.ps1" = "${claude}/hand-back.ps1";
      # Merged into ~/.claude.json by start-tests.ps1, not copied over it.
      ".claude/claude-state.json" = "${claude}/claude-state.json";
      ".claude/pool-key" = (import ../../myLib/claude-pool.nix).apiKeyFile;
      ".config/git/config" = "${claude}/gitconfig";
    };
  };
  # Keyboard and pointer as COSMIC has them (modules/hm-features/cosmic.nix),
  # in Windows' coarser steps. Acceleration is already off distro-wide.
  registry.defaultUser = {
    "Control Panel\\Keyboard" = {
      # 0-3 are 250-1000 ms in 250 ms steps; COSMIC's repeat_delay is 600.
      KeyboardDelay.sz = "1";
      # 0-31 run roughly linearly from 2.5 to 30 Hz; repeat_rate is 25.
      KeyboardSpeed.sz = "25";
    };
    # libinput's flat profile at speed 0.6042 is 1.6x. With acceleration off,
    # Windows' pointer speed steps are 1.25/1.5/1.75x at 11/12/13 (10 is 1x),
    # so 12 is the nearest.
    "Control Panel\\Mouse".MouseSensitivity.sz = "12";
  };
  # disk stays at the default, setup's interactive picker, for the USB ISO.
  # Its DiskID numbering isn't stable across boots, so wiping one by number
  # could hit the Linux SSD. build.install doesn't have that problem: the image
  # is set up in a sandboxed VM whose only disk is a scratch file.
}
