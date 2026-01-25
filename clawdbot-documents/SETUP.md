# Clawdbot Setup for Titan VM

This document describes the Clawdbot installation on the titan VM.

## What Was Configured

### 1. Flake Input
Added `nix-clawdbot` to `flake.nix`:
```nix
nix-clawdbot = {
  url = "github:clawdbot/nix-clawdbot";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

### 2. Home Manager Module
Created `homeManagerModules/features/clawdbot.nix` that:
- Imports the nix-clawdbot home-manager module
- Wraps it with myHomeManager options for easy configuration
- Manages Discord and Anthropic API credentials
- Configures systemd service for Linux

### 3. Documents Directory
Created `clawdbot-documents/` with:
- **AGENTS.md**: Agent configuration and capabilities
- **SOUL.md**: Bot personality and behavior guidelines
- **TOOLS.md**: Available tools and usage documentation
- **SETUP.md**: This file

### 4. Secrets Configuration
Added to `secrets.json`:
```json
{
  "clawdbot": {
    "discord_token": "YOUR_DISCORD_BOT_TOKEN_HERE",
    "discord_guild_id": "YOUR_DISCORD_GUILD_ID_HERE",
    "anthropic_api_key": "YOUR_ANTHROPIC_API_KEY_HERE"
  }
}
```

### 5. Titan VM Configuration
Enabled in `hosts/titan/home.nix`:
```nix
myHomeManager.clawdbot = {
  enable = true;
  discordToken = secrets.clawdbot.discord_token;
  discordAllowedGuilds = [ secrets.clawdbot.discord_guild_id ];
  anthropicApiKey = secrets.clawdbot.anthropic_api_key;
};
```

## Next Steps

### 1. Create Discord Bot

Follow these steps to create your Discord bot:

1. Go to https://discord.com/developers/applications
2. Click "New Application" and name it (e.g., "Clawdbot")
3. Go to "Bot" tab and click "Add Bot"
4. Click "Reset Token" and copy the token
5. Enable these Privileged Gateway Intents:
   - ✅ MESSAGE CONTENT INTENT
   - ✅ SERVER MEMBERS INTENT
   - ✅ PRESENCE INTENT

6. Go to "OAuth2" → "URL Generator"
7. Select scopes: `bot`, `applications.commands`
8. Select permissions:
   - Send Messages
   - Read Messages/View Channels
   - Attach Files
   - Embed Links
   - Read Message History
9. Copy the generated URL and invite the bot to your server

10. Get your Guild ID:
    - Enable Developer Mode in Discord (User Settings → Advanced)
    - Right-click your server icon
    - Click "Copy Server ID"

### 2. Get Anthropic API Key

1. Go to https://console.anthropic.com/settings/keys
2. Create a new API key
3. Copy the key (starts with `sk-ant-`)

### 3. Update Secrets

Edit `secrets.json` and replace the placeholders:
```json
{
  "clawdbot": {
    "discord_token": "YOUR_ACTUAL_DISCORD_BOT_TOKEN",
    "discord_guild_id": "YOUR_ACTUAL_GUILD_ID",
    "anthropic_api_key": "sk-ant-YOUR_ACTUAL_KEY"
  }
}
```

### 4. Build and Deploy

From your nixconf directory:

```bash
# Update flake inputs
nix flake update

# Build the titan configuration
nixos-rebuild build --flake .#titan

# Deploy to titan (if running on luna)
nixos-rebuild switch --flake .#titan --target-host titan --use-remote-sudo
```

Or if you're on titan directly:
```bash
sudo nixos-rebuild switch --flake ~/nixconf
```

### 5. Verify Installation

On the titan VM:

```bash
# Check if the service is running
systemctl --user status clawdbot-gateway

# View logs
journalctl --user -u clawdbot-gateway -f

# Check if the bot is connected
tail -f /tmp/clawdbot/clawdbot-gateway.log
```

### 6. Test the Bot

In your Discord server:
1. Send a message to the bot
2. The bot should respond (it will run a bootstrap ritual on first interaction)
3. Try commands like:
   - "What can you do?"
   - "Summarize https://example.com"
   - "What's the system status?"

## Configuration Options

### Enable/Disable Plugins

Edit `homeManagerModules/features/clawdbot.nix` to enable more plugins:

```nix
firstParty = {
  summarize.enable = true;   # Web/PDF/video summarization
  peekaboo.enable = true;    # Screenshots (Linux)
  oracle.enable = false;     # Web search
  poltergeist.enable = false; # UI automation (macOS only)
  sag.enable = false;        # Text-to-speech
  camsnap.enable = false;    # Camera snapshots
  gogcli.enable = false;     # Google Calendar
  bird.enable = false;       # Twitter/X
  sonoscli.enable = false;   # Sonos control
  imsg.enable = false;       # iMessage (macOS only)
};
```

### Add Custom Plugins

Add to the `plugins` list in the module:

```nix
plugins = [
  { source = "github:clawdbot/nix-steipete-tools?dir=tools/summarize"; }
  { source = "github:owner/your-custom-plugin"; }
];
```

### Change Model

Edit the module to override the default model:

```nix
configOverrides = {
  agents = {
    defaults = {
      model = {
        primary = "anthropic/claude-sonnet-4"; # Faster, cheaper
      };
    };
  };
};
```

## Troubleshooting

### Service Won't Start

Check logs:
```bash
journalctl --user -u clawdbot-gateway -n 50
```

Common issues:
- Missing or invalid Discord token
- Missing or invalid Anthropic API key
- Incorrect guild ID
- File permission issues

### Bot Doesn't Respond

1. Check if bot is online in Discord
2. Verify guild ID is correct
3. Check bot has proper permissions in the channel
4. Review logs for errors

### Permission Denied Errors

Ensure the secrets files are readable:
```bash
ls -la ~/.secrets/
chmod 600 ~/.secrets/clawdbot-*
```

## File Locations

- **Configuration**: `~/.clawdbot/clawdbot.json`
- **Workspace**: `~/.clawdbot/workspace/`
- **Skills**: `~/.clawdbot/workspace/skills/`
- **Logs**: `/tmp/clawdbot/clawdbot-gateway.log`
- **Secrets**: `~/.secrets/clawdbot-*`
- **Service**: `~/.config/systemd/user/clawdbot-gateway.service`

## Architecture

```
Discord → Bot Token → Clawdbot Gateway → Skills → Tools → System
                            ↓
                      Anthropic API
                      (Claude Opus 4.5)
```

The gateway:
1. Receives messages from Discord
2. Sends them to Claude for processing
3. Claude reads skills to understand available tools
4. Executes commands and returns results
5. Sends responses back to Discord

## Security Notes

- Secrets are stored in `~/.secrets/` (mode 600)
- Bot only responds in allowed guilds
- Commands run with user permissions (not root)
- All secrets are in git-crypt encrypted `secrets.json`

## Resources

- [nix-clawdbot GitHub](https://github.com/clawdbot/nix-clawdbot)
- [Clawdbot upstream](https://github.com/clawdbot/clawdbot)
- [Discord Developer Portal](https://discord.com/developers/applications)
- [Anthropic Console](https://console.anthropic.com)
