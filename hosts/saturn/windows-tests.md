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

## New in this build: letterboxing and screenshots (defenestrate 5780fa8, b086d9b)

Both are unit-tested only; nothing has run on Windows yet.

32. **League's client is letterboxed, not fought.** Open the League client
    (through the Riot Client) next to another window, so it sits in a
    half-width tile. It sits centred in the tile at its own size (past
    the tile's edges if it's wider), with no resize flicker. The other
    window keeps its whole half. `shell.log` has a `window 0x...: no WS_THICKFRAME,
    letterboxed at its own WxH` or `asked for ..., took ...: letterboxed`
    line for it, once per size, not repeating. Quote them and take a screenshot.
    Then focus the other window, switch to workspace 2 and back
    (Super+2, Super+1), and Super+Shift+Left/Right it: it stays centred
    at the same size each time, and no new letterbox lines appear (except
    one if its size actually changed). Riot Client's own window should do the same.
33. **Ordinary windows still fill their tiles.** A terminal and Firefox
    tiled side by side fill their tiles edge to edge. `shell.log` has no
    letterbox line for them. If it does, quote it: a window that only
    looked refused for a moment would stay small.
34. **PrintScreen opens the snip overlay.** Press PrintScreen (SendInput
    `VK_SNAPSHOT`, or ask Alex to press the physical key). The Snipping Tool's
    region overlay shows (screenshot). `shell.log` has `launched "ms-screenclip:"`
    or `launching "ms-screenclip:" failed: ...; starting "SnippingTool.exe /clip" instead`.
    Quote which one. Snip a region (drag across it): the snip is on the clipboard
    (`Get-Clipboard -Format Image` isn't empty) and a new file is in
    `Pictures\Screenshots`. If the URI "launched" but nothing showed, say so:
    the handler might need explorer, and then the fallback has to be forced.
    Win+Shift+S does the same.

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

## Firefox across reflashes (defenestrate 7059bfa, needs two reflashes)

Two reflashes, in this order. Neither has happened yet; mark them
**not checked** until the Linux side says it flashed for them.

39. **A fresh flash boots into a logged-in Firefox.** Flashed with
    `--no-keep` and an empty `~/.local/state/dfnstrate/persist/saturn-windows`
    (Zen closed), so the profile was seeded from Zen. Firefox opens on
    `Profiles\defenestrate.default-release` (`installs.ini` names it) and
    youtube.com shows Alex logged in with no clicks. Quote `profiles.ini`,
    `installs.ini`, and the profile folder's file list. A Google re-verify
    prompt counts as a pass; a logged-out page or a "Create profile"
    dialog is a fail.
40. **Logins survive a reflash.** Before the second reflash, log into a
    site on Windows that Linux isn't logged into (note which), and shut
    down fully. After flashing with no flags, that site is still logged
    in, YouTube too, and the profile folder has the same name as before.
    No "older version of Firefox" dialog. If this fails, the fallback is
    enrolling 1Password at first logon.

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
35. **Fresh install: Windows Firefox has uBlock Origin, SponsorBlock,
    Vimium, Refined GitHub, 1Password, Bitwarden and Firefox Multi-Account
    Containers installed and enabled without clicking.** They come from
    enterprise policy in `HKLM\SOFTWARE\Policies\Mozilla\Firefox`
    (`ExtensionSettings`, `DisableTelemetry`); quote `reg query` of that key.
    Then start Firefox and check `about:policies` shows both as active with
    no errors tab, and `about:addons` lists all seven enabled (screenshot
    both). Only on a reflashed install; on an existing one, note it as not
    checked.

## Pointer speed and key repeat from COSMIC's (needs a reflash)

defenestrate now converts cosmic-comp's `input_default` (libinput flat,
speed 0.6042271248762552, so 1.6042x) and xkb repeat into the new user's
registry at install; `dfnstrate update` doesn't carry it. Until a reflash
the old hand-picked values (MouseSensitivity 12, acceleration off) are
still there: say so and mark these **not checked**.

36. **The registry has the conversion.** `HKCU\Control Panel\Mouse`:
    MouseSpeed 1, MouseThreshold1/2 0, MouseSensitivity 10, and
    SmoothMouseXCurve/YCurve four equal steps (quote both as hex).
    `HKCU\Control Panel\Desktop`: Win8DpiScaling 1, LogPixels 96.
    `HKCU\Control Panel\Keyboard`: KeyboardDelay 1, KeyboardSpeed 25.
37. **Ratio measured, should be 1.00.** Run defenestrate's
    `bench/pointer/windows.ps1` (from the Linux checkout through `\\wsl$`)
    and ask Alex to do ten sideways strokes, stopping between them; quote
    its median px/count. On Linux, `bench/pointer/linux.py` with the same
    mouse gives the other figure (it's in the last report if Alex ran it,
    otherwise he runs it after the hand-back). Windows' median divided by
    Linux's should be 1.00 (±0.01). Expected on both: about 1.604. If
    Windows is off by exactly the display scale, Windows scales the curve
    differently than input.rs assumes.
38. **Nothing else changed with "Enhance pointer precision" on.** Ask Alex
    whether the pointer feels the same as on Linux, and whether any game's
    menu cursor feels different from before (some read the flag, or turn
    it off while they run, which would give them 1x instead of 1.6x).

## Last step

Once the report is finished, run
`powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/hand-back.ps1 -Report <the report's full path>`
and nothing else. It copies the report, its media folder, the Windows-side
logs and the Claude transcripts to the Linux side, then reboots to Linux.
Alex logs in there and picks the Linux session back up himself.
