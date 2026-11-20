# defenestrate: what to verify on this boot

You're Claude Code on saturn's Windows side, under defenestrate's shell (no
explorer), started at logon as the testing half of a Claude Code session on
the Linux side, which rebooted the machine into here to check the latest
defenestrate fixes on real hardware. Nobody may be at the screen. Work
through the list and check what you can yourself: logs, registry, tasks,
`wsl.exe`, and the UI itself (PowerShell with UI Automation to find and
click controls, SendInput for keys and mouse, screenshots to look). Never
wait for an answer; what only a person could judge (how smooth something
looks) is **not checked**, unless Alex happens to answer. Don't fix anything
on this side: the fixes go into defenestrate (github.com/cramt/defenestrate)
from Linux. Your job is an accurate report.

Logs: `%LOCALAPPDATA%\defenestrate\` (`shell.log`, `apps.log` plus a `winget\`
folder of per-ID logs, `wsl.log`, `reboot.log`) and
`%ProgramData%\defenestrate\linux-first.log`.

## Report

Write it to `\\wsl$\defenestrate\linux\home\cramt\.local\share\defenestrate\reports\`
as `<yyyy-mm-dd>-<hh-mm>.md` (create the folder if it's missing). That's the
Linux install's disk, so the Linux side reads it after the reboot. Writing
there is test 1. If it fails, say so in chat, save the report to
`%USERPROFILE%\defenestrate-report.md`, and say where it is in the
handoff (Last step can't work either then; don't reboot, leave it for Alex).

Create the report file before checking anything, and append each item as
you finish it: a run cut short (2026-11-20's was, before its report) still
leaves what it found.

Per item: **pass**, **fail**, or **not checked**, plus the evidence (a log
line, command output, or what Alex saw). On a failure, quote the relevant log
lines. Paraphrasing loses the detail the fix needs. Screenshots you took go
next to the report, in a `<report name>-media` folder. Put anything that looked
off but isn't on the list under "Also seen".

## New this boot

No reflash, and nothing in defenestrate changed since the last boot
(`~/.local/share/defenestrate/reports/2026-11-20-16-59-media/` on the
Linux side has its screenshots and drag timings; it found 15 fixed and 24
impossible: Settings, like every UWP app, won't start without explorer).
This boot tests the unattended loop itself. Don't redo the older items
below; only note anything that broke.

29. **You started on your own, with no setup questions.** Last time the
    theme and trust questions were gone but the bypass-permissions warning
    still needed Alex. Now `~/.claude/settings.json` has
    `skipDangerousModePermissionPrompt: true`. Quote it, and say whether
    anything at all asked for input before your first turn (you can tell:
    you started working without anyone answering). If Alex had to click
    something, he'll say so; put it in the report.
30. **The handoff.** Before the Last step, quote what's in
    `\\wsl$\defenestrate\linux\home\cramt\.local\state\next-boot\`
    (a `claude-resume.pending` should be there). The Last step renames it;
    list the folder again afterwards and quote that too, then reboot. The
    Linux side checks that its session came back on its own.

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

Once the report is written, hand back to Linux:

1. Rename `\\wsl$\defenestrate\linux\home\cramt\.local\state\next-boot\claude-resume.pending`
   to `claude-resume` (same folder). That's the Linux session asking to be
   resumed at the next login; renaming it is what wakes it. If it isn't
   there, nobody is waiting: skip this and say so in the report.
2. Run `schtasks /run /tn defenestrate-reboot-to-linux`, the launcher's
   "Reboot to Linux" task. The machine should come up in Linux (test 20:
   the Linux side checks it came back), and the resumed session reads your
   report.
