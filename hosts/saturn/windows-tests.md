# defenestrate: what to verify on this boot

You're Claude Code on saturn's Windows side, under defenestrate's shell (no
explorer). Alex booted in here to check the latest defenestrate fixes on real
hardware. Work through the list, check what you can yourself (logs, registry,
tasks, `wsl.exe`), and ask Alex for anything only a person at the screen can
see. Don't fix anything on this side: the fixes go into defenestrate
(github.com/cramt/defenestrate) from Linux. Your job is an accurate report.

Logs: `%LOCALAPPDATA%\defenestrate\` (`shell.log`, `apps.log` plus a `winget\`
folder of per-ID logs, `wsl.log`, `reboot.log`) and
`%ProgramData%\defenestrate\linux-first.log`.

## Report

Write it to `\\wsl$\defenestrate\linux\home\cramt\.local\share\defenestrate\reports\`
as `<yyyy-mm-dd>-<hh-mm>.md` (create the folder if it's missing). That's the
Linux install's disk, so the Linux side reads it after the reboot. Writing
there is test 1. If it fails, say so in chat, save the report to
`%USERPROFILE%\defenestrate-report.md`, and tell Alex where it is.

Per item: **pass**, **fail**, or **not checked**, plus the evidence (a log
line, command output, or what Alex saw). On a failure, quote the relevant log
lines. Paraphrasing loses the detail the fix needs. Put anything that looked
off but isn't on the list under "Also seen".

## New on this reflash

This install is a fresh reflash. The last boot's report
(`~/.local/share/defenestrate/reports/2026-11-17-21-58-logs/README.md` on
the Linux side) found three failures, now fixed. Check them first.

21. **The update is baked in.** `C:\Windows\Setup\defenestrate\updates.log`
    ends in `all installed`, and Windows is build 26300.9974: `UBR` under
    `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion` is 9974 (the ISO
    was 9457). Quote both.
22. **Automatic updates are off.** `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`
    has `NoAutoUpdate` = 1, and nothing is staged:
    `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired`
    doesn't exist.
23. **The logon task didn't die on the mount.** This logon's part of
    `wsl.log`: `mounting` with no `Resource busy` after it, the
    `restarting the defenestrate distro so \\wsl$ runs as the Linux user`
    line (fresh imports only; on 2026-11-19 it never came, because the old
    check asked `id -u`), then `copied ...` lines. You opening on your own (not started by Alex)
    is half the proof.

## Round two fixes (defenestrate 0e12cc5)

1. **`\\wsl$` reaches the install from Windows.** `dir \\wsl$\defenestrate\linux\home\cramt`
   lists the Linux home. Before this fix, the elevated logon task's mounts
   didn't show to non-elevated programs.
2. **Files written over `\\wsl$` belong to cramt, not root.** After writing the
   report: `wsl.exe -d defenestrate -- ls -ln /linux/home/cramt/.local/share/defenestrate/reports/<file>`
   shows the same uid (1000) as `ls -lnd /linux/home/cramt` (the distro's
   busybox has no `stat`). On a fresh reflash, test a file written before
   anything restarted the distro by hand: the 2026-11-19 boot only passed
   after test 4's `wsl -t`.
3. **WSL stays up.** `%USERPROFILE%\.wslconfig` has `instanceIdleTimeout=-1`
   under `[general]`. Close every WSL program, wait 2+ minutes,
   `wsl.exe -l -v`: `defenestrate` is still Running and
   `\\wsl$\defenestrate\linux` still lists files.
4. **A restarted distro remounts.** `wsl.exe -t defenestrate`, then
   `dir \\wsl$\defenestrate\linux\home`: the install is back without a
   logon (that's `dfn boot` from wsl.conf).
5. **Discord installed through the unelevated retry, once.** winget now
   runs with `--no-upgrade`: no upgrade attempts, and no Discord error
   dialogs every minute. `apps.log` shows
   `Discord.Discord` failing elevated, then succeeding unelevated, and
   `winget\Discord.Discord.unelevated.*` exists. Discord starts. The
   scheduled task `defenestrate-apps` is gone (`schtasks /query /tn defenestrate-apps`
   errors), because it deletes itself once every app is in. If it's
   still there, list which IDs `apps.log` says are left.
6. **Discord's updater box floats, Discord's main window tiles.** Ask Alex.
   `shell.log` has a verdict line per new window; quote both Discord ones.
7. **Topmost windows float.** Anything always-on-top (a splash screen,
   Riot Client's loading box) floats. Quote the `shell.log` verdicts for
   whatever topmost windows appeared.
8. **Launcher.** Ask Alex to tap Super and open a few things: Firefox,
   Discord, "Linux terminal". All open. Not "Reboot to Linux": you run
   that same task yourself at the very end. The launcher now opens shortcuts through
   ShellExecuteEx, as explorer does.
9. **Dark mode.** `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`:
   `AppsUseLightTheme` and `SystemUsesLightTheme` are both 0. Firefox and
   Settings-style windows are dark (ask Alex).

## New in this build: autostart (defenestrate 7727f16)

The shell now runs what explorer would at logon. You're the proof it ran
the config's line: it opened this console.

18. **The shell's autostart log.** `shell.log` has `autostart (...)` lines
    for this logon: the Run keys, Startup folders, then `autostart (config)`.
    Quote them. `reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
    and the Startup folders (`shell:startup`) list what should have started;
    each entry there is running (`Get-Process`), or the log says why it isn't
    (disabled in Task Manager).
19. **Discord started at logon** if it registered itself in HKCU Run (it
    usually does after its first run).

## Round one fixes, to check they held

10. Monitor runs at 240 Hz, not 60 (`shell.log` lists displays; or ask Alex).
11. Fixed-size app windows (League/Riot client, installers) tile; real
    dialogs float.
12. Apps winget put on PATH work in a new console without a logout
    (`git --version`, `claude --version`).
13. Protected windows (a game with anti-cheat) tile.

## Never seen on real hardware yet

14. **AMD GPU driver.** Device Manager / `Get-PnpDevice -Class Display`
    shows the Radeon on AMD's driver, not "Microsoft Basic Display Adapter".
    `apps.log` has the Windows Update display-driver pass result.
15. **Animations.** Ask Alex whether tiling, maximize and workspace slides
    look smooth at 240 Hz or stutter.
16. **Linux stays first in boot order.** `linux-first.log` shows the startup
    task putting the Linux entry back first (or finding it already first).
17. **`wsl.linux.files` copy.** `wsl.log` shows the profile copies, and
    `%USERPROFILE%\.claude\CLAUDE.md` matches the Linux render (you're
    reading proof of this one).

## Last step

Once the report is written and Alex has read it, run
`schtasks /run /tn defenestrate-reboot-to-linux`. That's the launcher's
"Reboot to Linux" task, and the machine should come up in Linux (test 20:
the Linux side checks it came back).
