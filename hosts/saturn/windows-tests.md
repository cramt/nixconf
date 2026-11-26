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

## New in this build: letterboxing and screenshots (defenestrate 0d23b4a, b086d9b)

5780fa8's letterbox failed on the 2026-11-26 boot (League's game over its
neighbour and off the screen, the console stuck narrow); 0d23b4a replaces it.
Unit-tested only; the new version hasn't run on Windows yet.

32. **League letterboxed only if it refuses its tile, never off the screen.**
    Open the League client (through the Riot Client) next to another window,
    so it sits in a half-width tile, then start a game (windowed 2560x1440
    in `game.cfg`). Every window is asked for its tile's size first now:
    quote `shell.log`'s `window 0x...:` fit lines for the client, Riot
    Client and the game (`asked for WxH, took WxH (style ...): letterboxed`
    or `fills its tile`), once per size, not repeating. For each, quote its
    window rect, client rect and `DWMWA_EXTENDED_FRAME_BOUNDS` with the
    monitor's: nothing may reach past the monitor (0,0-5120,1440), and
    nothing may cover the other half except by however much the window is
    wider than its tile. The game's expected outcome is `fills its tile` at
    2560x1440 (client 2560,0 2560x1440). Then focus the other window, switch
    to workspace 2 and back (Super+2, Super+1), and Super+Shift+Left/Right
    the letterboxed one: it stays at the same size each time, kept on the
    screen, and no new fit lines appear (except one if its size actually
    changed). In game, ask Alex: can she click along the bottom edge, and
    does the camera pan at the bottom and right edges? (The overflow was
    fixed; whether it caused the dead bottom edge is unproven.) Screenshot.
33. **Ordinary windows fill their tiles, through style changes and tile
    growth.** Open a cmd console (Super+T, then `claude` in it) and Firefox
    side by side, then a third window, then close the third: both fill their
    tiles edge to edge each time, and the console grows to its whole half
    when its tile does. `shell.log` has no `letterboxed` line for either;
    a `fills its tile` line after a style change is fine. If a letterbox line
    appears for one, quote it with the window's style before and after:
    a window that only looked refused for a moment would stay small.
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

## Pointer speed and key repeat from COSMIC's (an update or a reflash)

defenestrate now converts cosmic-comp's `input_default` (libinput flat,
speed 0.6042271248762552, so 1.6042x) and xkb repeat into the user's
registry, at install and, through the boot queue (below), on
`dfnstrate update`. If neither has happened since, the old hand-picked
values (MouseSensitivity 12, acceleration off) are still there: say so and
mark these **not checked**.

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

## Boot queue: registry config through `dfnstrate update` (defenestrate boot-actions)

`update` now queues changed registry imports under
`C:\Windows\Setup\defenestrate\boot\machine` and `\user`, run once each
by the tasks `defenestrate-boot` (SYSTEM, startup) and
`defenestrate-boot-user` (the user, logon); logs
`%ProgramData%\defenestrate\boot-machine.log` and `boot-user.log`. An install
flashed before the queue gets the tasks registered by
`defenestrate-linux-first` at the first startup after the update
(`linux-first.log` says "registering the boot queue"), which also runs that
boot's machine phase; the user phase may then only run at the logon after.
Only check these after an `update`; on a fresh flash 41 and 42 still apply
(the image's own queue runs at its first boot).

41. **Each action ran once.** Quote both boot logs. `boot-machine.log`: one
    "running"/"done" pair each for the software, system and shell imports;
    `boot-user.log`: one for the user import, followed by an
    `SPI_SETMOUSE`, `SPI_SETMOUSESPEED`, curve, `SPI_SETKEYBOARDDELAY` and
    `SPI_SETKEYBOARDSPEED` line, and "in effect from the next logon" lines
    for LogPixels and Win8DpiScaling. No "FAILED". `dir` both queue
    folders: every `.json` has a `.done` next to it. Also
    `schtasks /query /tn defenestrate-boot` and `defenestrate-boot-user`
    both exist.
42. **The values are in the registry and in effect without a logout.** Item
    36's values, and in PowerShell (not elevated) read the live ones:
    `Add-Type -Namespace T -Name S -MemberDefinition '[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint u, int[] p, uint f); [DllImport("user32.dll", EntryPoint="SystemParametersInfoW")] public static extern bool Get(uint a, uint u, ref int p, uint f);'`,
    then `$m = [int[]]::new(3); [T.S]::SystemParametersInfo(3,0,$m,0); $m`
    (expect 0 0 1), and `$v = 0; foreach ($a in 0x70, 0x16, 0x0A) { [void][T.S]::Get($a,0,[ref]$v,0); $v }`
    (MouseSensitivity 10, KeyboardDelay 1, KeyboardSpeed 25). Ask Alex
    whether the pointer already felt like Linux's in this first session
    after the update, or only after logging out and in (that's whether the
    curve took effect from the SPI refresh, which isn't confirmed).
43. **A second boot runs nothing.** After a reboot into Windows with no
    `update` in between (ask Alex, or check the timestamps), both logs end
    in "nothing pending" and no action was run a second time.
44. **The queue's files are admin-only.** `icacls` on
    `C:\Windows\Setup\defenestrate\boot\user` and one `.reg` in it: SYSTEM
    and Administrators full, Users read and execute at most, no Everyone.

## Cursor lock and Firefox's second launch (defenestrate 0d23b4a)

45. **The game keeps the cursor locked.** In a League game (item 32), log
    `GetForegroundWindow` and `GetClipCursor` every 50 ms for a few
    minutes while Alex plays, as last boot's `cursor-clip.log` did. The
    clip stays the game's window rect and the foreground stays the game
    the whole time Alex doesn't Alt+Tab, including when she pushes the
    pointer against the left edge of the game's half for a few seconds
    (ask her to). With `focus_follows_cursor` on, `shell.log` has no
    focus change to the neighbour then. Then Alt+Tab out (the lock goes,
    expected) and back (it returns). Quote the samples around each switch
    and ask Alex whether the lock ever slipped without her switching.
46. **A second Firefox launch opens a window in the running one.** With
    the autostarted Firefox running, open Firefox from the launcher: a new
    window opens in the running Firefox, no "Close Firefox" dialog, and no
    second `firefox.exe` remains after 10 s. Quote `shell.log`'s
    `autostart` and `started`/`launched` lines for Firefox (each now says
    `integrity 0x..., uiAccess N`) and every `MozillaDialogClass` verdict
    line (now with its pid, and logged again if its title changes). Also
    quote `Get-CimInstance Win32_Process -Filter "name='firefox.exe'" |
    Select ProcessId,ParentProcessId,CreationDate,CommandLine`. If the
    dialog still comes: how long after the launch line (last time 5.26 s,
    Firefox's 5 s startup lock, meaning the first Firefox hadn't finished
    starting), which pid shows the untitled dialog at logon and what its
    title became, whether a `dialog 0x... was under tile(s)` line shows
    the shell lifting it, and whether that pid is the one holding up
    startup (it's still running and the browser window belongs to another
    pid, or the same one).

## Last step

Once the report is finished, run
`powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/hand-back.ps1 -Report <the report's full path>`
and nothing else. It copies the report, its media folder, the Windows-side
logs and the Claude transcripts to the Linux side, then reboots to Linux.
Alex logs in there and picks the Linux session back up himself.
