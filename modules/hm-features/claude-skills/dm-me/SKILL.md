---
name: dm-me
description: Send Alex a Discord DM via the "yelliv" bot. Use when the user says "DM me", "ping me on Discord", "message me when done", or asks to be notified on Discord after a long-running task finishes.
---

# dm-me

Sends a direct message to Alex (Discord user ID `149996010314137600`) through the
**yelliv** bot.

## How to send

Run `dm-me` (on PATH, curl/jq/op bundled) with the message as a single argument:

```bash
dm-me "✅ build finished — eros is green"
```

## Token resolution

`dm-me` resolves the bot token declaratively — never hardcoded, and without an
interactive 1Password prompt:

1. `$YELLIV_BOT_TOKEN` env var — explicit override for hosts without 1Password.
2. Otherwise `op read 'op://Homelab/OpenClaw-Discord/botToken'`, run **non-interactively**
   by exporting `OP_SERVICE_ACCOUNT_TOKEN` from `/etc/opnix-token` (the opnix-materialized
   service-account token — same mechanism as the repo's `just tf` recipe). This is why
   there's no desktop-app approval prompt per call.

If neither path yields a token it exits non-zero — surface that to the user.

## Gotchas

- The bot can only DM Alex if **yelliv shares a Discord server with her**. A
  `50278 "no mutual guilds"` error means the bot was removed from the shared server;
  re-invite it: `https://discord.com/api/oauth2/authorize?client_id=1498405029374197871&scope=bot&permissions=0`
- Keep messages concise. Send only meaningful notifications (done / needs-attention),
  not routine progress chatter.
