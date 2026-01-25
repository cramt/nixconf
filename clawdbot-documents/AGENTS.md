# Agent Configuration

This document describes the AI agents available in this Clawdbot instance.

## Primary Agent

The primary agent is configured to use Claude Opus 4.5 for complex reasoning and task execution.

### Model Configuration

- **Model**: `anthropic/claude-opus-4-5`
- **Thinking Level**: `high` (enables extended reasoning for complex tasks)
- **Provider**: Anthropic

### Capabilities

The agent has access to:
- System command execution
- File operations
- Web browsing and summarization
- Screenshot capabilities (Linux)
- Discord integration

### Workspace

The agent operates in `~/.clawdbot/workspace` with access to:
- Skills directory for tool documentation
- State management for conversation context
- Plugin-provided tools and utilities

## Configuration Options

### Model Selection

You can override the model in your Nix configuration:

```nix
myHomeManager.clawdbot = {
  # Model options:
  # - anthropic/claude-opus-4-5 (most capable, slower, expensive)
  # - anthropic/claude-sonnet-4 (balanced)
  # - anthropic/claude-haiku-4-5 (fastest, cheapest)
};
```

### Thinking Levels

- `off`: No extended thinking
- `minimal`: Brief reasoning
- `low`: Light reasoning
- `medium`: Moderate reasoning
- `high`: Deep reasoning (default)

## Security

- Discord bot token stored in `~/.secrets/clawdbot-discord-token`
- Anthropic API key stored in `~/.secrets/clawdbot-anthropic-key`
- Access controlled via Discord guild allowlist
