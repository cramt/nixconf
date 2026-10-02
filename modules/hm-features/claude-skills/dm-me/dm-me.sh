# Send a Discord DM to Alex via the "yelliv" bot.
# Usage: dm-me "your message"
set -euo pipefail

msg="${1:?usage: dm-me <message>}"
recipient="149996010314137600"   # Alex's Discord user ID

# Load the opnix service-account token (materialized at /etc/opnix-token) so `op`
# runs non-interactively — same pattern as the repo's `just tf` recipe. This
# avoids the 1Password desktop-app approval prompt on every call.
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && [ -r /etc/opnix-token ]; then
  OP_SERVICE_ACCOUNT_TOKEN="$(cat /etc/opnix-token)"
  export OP_SERVICE_ACCOUNT_TOKEN
fi

# Resolve the bot token. An explicit env var wins (servers without 1Password);
# otherwise read it declaratively from the Homelab vault via the service account.
if [ -n "${YELLIV_BOT_TOKEN:-}" ]; then
  tok="$YELLIV_BOT_TOKEN"
else
  tok="$(op read 'op://Homelab/OpenClaw-Discord/botToken')"
fi

# Open (or reuse) the DM channel, then post. jq builds the JSON so emoji /
# quotes / newlines in the message are escaped safely.
cid="$(curl -fsS -X POST \
  -H "Authorization: Bot $tok" -H "Content-Type: application/json" \
  -d "{\"recipient_id\":\"$recipient\"}" \
  "https://discord.com/api/v10/users/@me/channels" | jq -r '.id')"

curl -fsS -X POST \
  -H "Authorization: Bot $tok" -H "Content-Type: application/json" \
  --data "$(jq -nc --arg c "$msg" '{content:$c}')" \
  "https://discord.com/api/v10/channels/$cid/messages" >/dev/null

echo "dm-me: delivered to $recipient"
