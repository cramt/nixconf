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

Keep it on this disk, at `%USERPROFILE%\defenestrate-report\<yyyy-mm-dd>-<hh-mm>.md`:
over `\\wsl$` only creating new files has been reliable (renames silently
don't happen, and the last report stopped after its first item). The Last
step's script copies it to the Linux side, with the logs and your
transcript. Screenshots go in a `<report name>-media` folder next to it,
which the script copies too.

Create the report file before checking anything, and add each item as you
finish it: a run cut short still leaves what it found.

Per item: **pass**, **fail**, or **not checked**, plus the evidence (a log
line, command output, or what Alex saw). On a failure, quote the relevant log
lines. Paraphrasing loses the detail the fix needs. Put anything that looked
off but isn't on the list under "Also seen".

## New this boot

No reflash; `dfnstrate update` patched the WSL payload and the reboot task.
Why the last three boots never handed back: "Reboot to Linux" killed WSL's
VM with the Linux install still mounted, and btrfs writes back every 30 s,
so whatever was written to Linux in the last half minute (the report's
last items, the handoff rename) was lost, though it looked done from here.
The reboot task now unmounts it first (`dfn release`). Nothing for you to
check about that: the Linux side reads `reboot.log` afterwards with
`dfnstrate logs`. The rootfs changed, so this logon re-imported the
distro (`wsl.log`). Don't redo the older items below; only note anything
that broke. This boot tests the loop:

29. **You started on your own, with no setup questions,** and on this
    logon's copy of the plan: `%LOCALAPPDATA%\defenestrate\linux-files.txt`'s
    time is after this boot (`(Get-CimInstance Win32_OperatingSystem).LastBootUpTime`);
    quote both. Quote `skipDangerousModePermissionPrompt` from
    `~/.claude/settings.json` and the `C:/Users/cramt` entry in
    `~/.claude.json`.
31. **Default apps are off.** The shell no longer tries to open Settings
    (it can't start without explorer, last report): `shell.log` has no
    `default apps:` line this logon, and no `SystemSettings` process is
    hanging around (`Get-Process SystemSettings`). Quote both.

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

Once the report is finished, run
`powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/hand-back.ps1 -Report <the report's full path>`
and nothing else. It copies the report, its media folder, the Windows-side
logs and the Claude transcripts to the Linux side, then reboots to Linux.
Alex logs in there and picks the Linux session back up himself.
