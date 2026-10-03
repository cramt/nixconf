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
service when ganymede's graphical session starts. A pairing made by PIN in
either UI lasts until the next restart.

saturn's web UI login (port 47990) comes from the same 1Password item:
`username` and `password`, which `sunshine-seed` hashes into the
`web_ui_login.json` file that Sunshine reads.

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
