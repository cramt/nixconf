# Moonlight to Sunshine pairing

ganymede's Moonlight is paired with saturn's Sunshine ahead of time, so
nobody ever enters a PIN. A pairing is two self-signed certificates that each
side pins:

| | saturn (Sunshine) | ganymede (Moonlight) |
| --- | --- | --- |
| Own cert | `cert` setting, from `moonlight-pairing.json` | `certificate` in Moonlight.conf, from `moonlight-pairing.json` |
| Own key | `pkey` setting, opnix `op://Homelab/Sunshine-saturn/sunshine-key.pem` | `key` in Moonlight.conf, opnix `op://Homelab/Moonlight-ganymede/moonlight-ganymede.pem` |
| The other side | `root.named_devices` in `sunshine_state.json` holds ganymede's cert | the `hosts` entry holds saturn's cert, uuid, address and MAC |

`modules/gaming/moonlight-pairing.json` holds the certs and ids. None of it is
secret. The two private keys live only in 1Password.

Both sides write the pairing back into their files at every start:
`sunshine-seed` before Sunshine starts, and the `moonlight-pairing` user
service when ganymede's graphical session starts. On ganymede that touches
only the client identity and saturn's `hosts` entry, so other PCs paired by
PIN stay paired (see below). Re-pairing saturn itself by PIN in either UI
lasts only until the next restart.

saturn's web UI login (port 47990) comes from the same 1Password item:
`username` and `password`, which `sunshine-seed` hashes into the
`web_ui_login.json` file that Sunshine reads.

## Games on Home

Home's Games aren't listed in nix. The `emrakul-games` user service
(`packages/emrakul-games`, wired in `hosts/ganymede/moonlight.nix`) reads
every paired host and the client cert and key from Moonlight.conf, asks each
host's Sunshine for its app list (`/applist`) and box art (`/appasset`), and
writes one desktop entry per app into
`~/.local/state/emrakul-games/share/applications`. Home reads that dir along
with the nix-built one, and picks up changes within a few seconds.

It runs at session start, whenever Moonlight rewrites Moonlight.conf (a new
pairing, say), and every 5 minutes. Which hosts count, and what happens to
their apps:

- A host counts when Moonlight.conf holds its server cert, that is, once it
  is paired. Hosts Moonlight only found on the LAN don't.
- A host that doesn't answer (asleep, switched off) keeps the apps it last
  listed, so the tiles stay and Moonlight can wake it with Wake-on-LAN. An
  app goes only when its host answers without it, or when the host is
  unpaired in Moonlight.
- Apps hidden in Moonlight's app grid get no tile.
- A tile is named after the app. An app name on more than one host (every
  Sunshine has "Desktop") gets the host's name after it, as Moonlight shows
  it: "Desktop (saturn)". When two hosts also share a name, the address is
  added too. Rename one in Moonlight to fix that.
- The tile shows the app's box art on its average colour. Without box art,
  or with Sunshine's small placeholder, it shows Moonlight's logo.

saturn's apps still come from `hosts/saturn/games.nix`, on saturn's side.

To see what it did: `journalctl --user -u emrakul-games` on ganymede.

Its units hang off `graphical-session.target`, which outlives an emrakul
restart while any other session (an ssh login) keeps the user manager up.
A deploy that changes them takes effect at the next boot, or straight away
with `systemctl --user restart emrakul-games.path emrakul-games.timer
emrakul-games.service` as cramt.

## Pair another PC by PIN

For a PC whose Sunshine isn't in nix, such as the second PC that also calls
itself saturn (`hosts/saturn/lan.nix`). Its tiles appear on their own once it
is paired.

1. On ganymede's Home, open the **Moonlight** tile. Moonlight's own window
   opens, and the controller drives it: D-pad or left stick to move, A to
   select, B to go back.
2. The PC shows up in the grid with a padlock once Moonlight finds it on the
   LAN; its Sunshine has to be running. Select it. Moonlight shows a 4-digit
   PIN.
3. On that PC, open Sunshine's web UI (`https://localhost:47990`), go to
   **PIN**, enter the PIN and a name for the device (ganymede), and send it.
4. Moonlight shows the PC unlocked. Optionally rename it in Moonlight
   (focus it, X for its menu, **Rename PC**) so its tiles aren't also named
   "saturn".
5. Press the Steam button to go back Home. The PC's apps appear as tiles
   within a few seconds.

The pairing uses ganymede's pre-generated client cert, so it outlives
session restarts and deploys. Rotating that cert (below) unpairs every PC
paired this way; pair them again by PIN afterwards.

## Create or rotate the pairing

1. Generate new certs into a new private dir:

   ```sh
   nix run .#moonlight-pairing -- ~/.cache/moonlight-pairing/$(date +%F)
   ```

2. Copy its `public.json` over `modules/gaming/moonlight-pairing.json`.

3. Put the keys into 1Password from that dir. The first time, create the items:

   ```sh
   cd ~/.cache/moonlight-pairing/<dir>
   op item create --vault Homelab --category Login --title Sunshine-saturn \
     --generate-password='letters,digits,32' username=cramt \
     'sunshine-key\.pem[file]=sunshine-key.pem'
   op item create --vault Homelab --category 'Secure Note' --title Moonlight-ganymede \
     'moonlight-ganymede\.pem[file]=moonlight-ganymede.pem'
   ```

   Keep the backslash. In an `op` assignment a dot separates section from
   field, so an unescaped `sunshine-key.pem[file]` is stored as file `pem` in
   section `sunshine-key`, and opnix fails with `missing_reference`.

   To rotate, replace the `.pem` files on the existing items in the 1Password
   app, or `op item delete` both items and create them again as above (which
   also rolls the web UI password).

4. Commit, deploy both hosts, then on each run
   `systemctl restart opnix-secrets`. On saturn, restart Sunshine as the user
   (`systemctl --user restart sunshine`). On ganymede, restart the session
   (`systemctl restart emrakul`).

5. Delete the private dir.

## Adding a client

Name it on the generator's command line (`... <dir> ganymede <host>`), which
pairs every listed client in one go. Then set `myNixOS.moonlight` on the new
host with `clientKey` pointing at its own 1Password file.
