#!/usr/bin/env bash
set -euo pipefail

# Setup script for opnix on luna
# Run this on your local machine — it creates the service account,
# then SSHes into luna to install the token.

LUNA_HOST="${LUNA_HOST:-root@192.168.178.24}"
VAULT="Homelab"
SA_NAME="opnix-luna"

echo "==> Creating 1Password service account '${SA_NAME}' with read-only access to '${VAULT}'..."
TOKEN=$(op service-account create "$SA_NAME" --vault "${VAULT}:read_items" --raw)

echo "==> Installing token on luna at /etc/opnix-token..."
echo "$TOKEN" | ssh "$LUNA_HOST" 'cat > /etc/opnix-token && chmod 0640 /etc/opnix-token'

echo "==> Done. Token installed at ${LUNA_HOST}:/etc/opnix-token"
echo ""
echo "Next steps:"
echo "  1. Run 'just inject_secrets' to generate secrets.json"
echo "  2. Run 'nix flake update opnix' to lock the opnix input"
echo "  3. Run 'just build_luna' to deploy"
