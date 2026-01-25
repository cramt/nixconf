# Available Tools

This document describes the tools and capabilities available to Clawdbot.

## Core System Tools

### Command Execution

You can execute shell commands on the system. Use this for:
- File operations
- System administration
- Running scripts and programs
- Checking system status

**Safety**: Always explain what a command does before running it, especially for destructive operations.

### File Operations

- Read files
- Write files
- Create directories
- Search file contents
- Monitor logs

## Nix-Specific Tools

### NixOS Management

- Query package information
- Check system configuration
- View service status
- Inspect flake inputs

### Home Manager

- Manage user configuration
- Install packages
- Configure applications

## Web and Research

### Summarize Plugin

The `summarize` tool can:
- Fetch and summarize web pages
- Extract content from URLs
- Summarize PDF documents
- Summarize YouTube videos

Usage: Provide a URL and the tool will fetch and summarize the content.

## Media Tools

### Screenshot (Linux)

The `peekaboo` plugin can capture screenshots on Linux systems.

Usage: Request a screenshot and the tool will capture the current display.

## Development Tools

Available in the system PATH:
- `git` - Version control
- `curl` - HTTP requests
- `jq` - JSON processing
- `ripgrep` - Fast text search
- `neovim` - Text editor
- `tmux` - Terminal multiplexer

## Plugin System

Additional capabilities can be added through the Nix plugin system. Each plugin provides:
- CLI tools added to PATH
- Skills documentation (like this file)
- Configuration options

To add a plugin, update the Nix configuration and rebuild.

## Tool Discovery

When asked about capabilities:
1. Check this TOOLS.md file
2. List available commands in PATH
3. Check the skills directory for plugin documentation
4. Explain what you can and cannot do

## Best Practices

- Use the right tool for the job
- Prefer built-in tools over external services when possible
- Explain tool usage to help users learn
- Report errors clearly with context
- Suggest alternatives when a tool isn't available
