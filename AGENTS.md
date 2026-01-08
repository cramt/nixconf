# AI Coding Agents Configuration

This document describes the AI coding agents configured in this NixOS setup.

## Available Agents

### 1. OpenCode (CLI)
- **Location**: `homeManagerModules/features/opencode.nix`
- **Package**: Terminal-based AI coding assistant with multi-provider support
- **Config file**: `~/.config/opencode/config.json` (managed by Home Manager)
- **Auth file**: `~/.local/share/opencode/auth.json` (managed by CLI)

**Providers**:
- **Anthropic Claude**: Claude Opus 4.5, Sonnet 4, Haiku 4.5 (Subscription-based)
- **Google Gemini**: Gemini 2.0 Flash, Gemini 2.0 Pro (Free tier)
- **GitHub Copilot**: GPT-4o, Claude 3.5 Sonnet (Requires subscription)
- **Ollama**: gpt-oss:20b (Local)

**Usage**:
```bash
opencode                    # Start OpenCode CLI
opencode --version          # Check version
```

**In-CLI Commands**:
- `/models` - List all available models across providers
- `/provider <name>` - Switch to a different provider
- `@<file>` - Reference files in prompts
- `/help` - Show all available commands

**Authentication**:
- **Claude & Gemini**: Environment variables from secrets.json (automatic)
- **GitHub Copilot**: Run `opencode auth login` and authenticate via device flow
- **Ollama**: Local, no authentication needed

### 2. Claude Code
- **Location**: `homeManagerModules/bundles/development.nix:53`
- **Package**: Official Anthropic terminal-based agentic IDE
- **Provider**: Anthropic Claude (subscription or API key)

**Usage**:
```bash
claude-code                 # Start Claude Code
```

### 3. Zed Editor Agent
- **Location**: `homeManagerModules/features/zed.nix`
- **Integration**: Built into Zed editor
- **Providers**: Google Gemini (gemini-3-pro, gemini-2.0-flash)

**Usage**:
- Open Zed editor
- Use AI agent features within the editor
- Configured for Gemini models

### 4. Avante (Neovim)
- **Location**: `homeManagerModules/features/neovim/default.nix`
- **Integration**: Neovim plugin (nvf framework)
- **Provider**: Google Gemini (API key via environment variable)

**Usage**:
- Open Neovim
- AI assistant available via avante-nvim plugin
- Uses GEMINI_API_KEY environment variable

### 5. Codex
- **Location**: `homeManagerModules/features/codex.nix`
- **Package**: Terminal-based AI coding assistant
- **Provider**: Local Ollama (gpt-oss:20b model)

**Usage**:
```bash
codex                       # Start Codex CLI
```

### 6. Ollama Service
- **Location**: `nixosModules/services/ollama.nix`
- **Type**: System service (NixOS)
- **Port**: 11434
- **GPU**: ROCm support enabled (for AMD GPUs)
- **Model**: qwen3:8b (auto-loaded)

**Usage**:
```bash
ollama list                 # List installed models
ollama run <model>          # Run a model directly
ollama serve                # Service runs automatically
```

## Secrets Management

AI provider credentials are stored in git-crypt encrypted `secrets.json`:

```json
{
  "opencode": {
    "anthropic_api_key": "sk-ant-...",
    "gemini_api_key": "AIza..."
  }
}
```

**To update secrets**:
```bash
cd ~/nixconf
git-crypt unlock            # Unlock if needed
vim secrets.json            # Edit secrets
git-crypt status            # Verify encryption
sudo nixos-rebuild switch --flake ~/nixconf
```

**Where to get API keys**:
- **Anthropic**: https://console.anthropic.com/settings/keys
- **Gemini**: https://aistudio.google.com/app/apikey
- **GitHub Copilot**: Managed via GitHub subscription (no API key needed)

## Provider Selection Strategy

Different agents are optimized for different tasks:

### When to use OpenCode with Claude
- Complex reasoning and architectural design
- Long-form code generation
- Refactoring large codebases
- High-quality documentation generation

### When to use OpenCode with Gemini
- Quick iterations and prototyping
- Fast responses (free tier)
- Exploratory coding
- Cost-sensitive tasks

### When to use OpenCode with Copilot
- Repository-aware suggestions
- Context from GitHub repos
- Access to multiple models (GPT-4o, Claude 3.5)
- Experimental features

### When to use Ollama (local)
- Privacy-focused development
- Offline work
- No external API dependencies
- Local model experimentation

### When to use Claude Code
- Official Anthropic terminal experience
- Full agentic IDE features
- Integrated development workflow

### When to use Zed Agent
- Inline editing within Zed
- Integrated development with AI
- Fast, lightweight editor experience

### When to use Avante (Neovim)
- Vim/Neovim workflow integration
- Modal editing with AI assistance
- Terminal-based development

### When to use Codex
- Quick terminal-based AI queries
- Local Ollama integration
- Simple coding assistance

## Configuration Architecture

### Module Structure
All configurations follow the `myLib.extendModules` pattern:
- Feature modules in `homeManagerModules/features/`
- Auto-enabled via bundles in `homeManagerModules/bundles/development.nix`
- Each module gets automatic `myHomeManager.<name>.enable` option
- Services use systemd units for auto-start

### OpenCode Configuration Flow
1. **Nix module** (`opencode.nix`) → declares providers and settings
2. **Home Manager** → writes `~/.config/opencode/config.json`
3. **Environment variables** → set `ANTHROPIC_API_KEY` and `GEMINI_API_KEY`
4. **CLI authentication** → run `opencode auth login` for GitHub Copilot
5. **Auth storage** → tokens saved in `~/.local/share/opencode/auth.json`

### File Locations
- OpenCode config: `~/.config/opencode/config.json`
- OpenCode auth: `~/.local/share/opencode/auth.json`
- OpenCode cache: `~/.cache/opencode/`
- Secrets (encrypted): `~/nixconf/secrets.json`

## Post-Setup Verification

After rebuilding your NixOS configuration, verify everything works:

```bash
# 1. Check OpenCode is installed
opencode --version

# 2. Verify config was generated
cat ~/.config/opencode/config.json

# 3. Check environment variables
echo $ANTHROPIC_API_KEY
echo $GEMINI_API_KEY

# 4. Authenticate GitHub Copilot
opencode auth login         # Select GitHub

# 5. Test providers
opencode
# In OpenCode CLI, run:
# /models                   # Should show all providers
# /provider anthropic       # Switch to Claude
# /provider gemini          # Switch to Gemini

# 6. Verify secrets are encrypted
cd ~/nixconf
git-crypt status           # secrets.json should show as encrypted
```

## Troubleshooting

### OpenCode not found
```bash
# Check if package is available
nix search nixpkgs opencode

# If not, may need unstable
nix search nixpkgs#unstable opencode
```

### Environment variables not set
```bash
# Check if secrets loaded correctly
cd ~/nixconf
git-crypt unlock
cat secrets.nix             # Should show: builtins.fromJSON (builtins.readFile ./secrets.json)

# Rebuild and reload shell
sudo nixos-rebuild switch --flake ~/nixconf
exec $SHELL                 # Reload shell to get new env vars
```

### GitHub Copilot authentication fails
```bash
# Ensure you have an active Copilot subscription
# Run authentication flow
opencode auth login
# Select GitHub and follow device flow

# Check auth status
opencode auth list
```

### Config not applied
```bash
# Home Manager may need explicit switch
home-manager switch --flake ~/nixconf

# Or rebuild entire system
sudo nixos-rebuild switch --flake ~/nixconf
```

### Provider models not showing
```bash
# Check config file
cat ~/.config/opencode/config.json | jq '.provider'

# Should show all four providers: anthropic, gemini, copilot, ollama
```

## References

- [OpenCode Documentation](https://opencode.ai/docs/)
- [OpenCode Providers](https://opencode.ai/docs/providers/)
- [OpenCode Config Schema](https://opencode.ai/config.json)
- [Home Manager OpenCode Module](https://github.com/nix-community/home-manager/blob/master/modules/programs/opencode.nix)
- [Anthropic API Documentation](https://docs.anthropic.com/claude/reference/)
- [Google Gemini API](https://ai.google.dev/gemini-api/docs)
- [GitHub Copilot](https://github.com/features/copilot)
- [Ollama Documentation](https://ollama.ai/docs)

## Future Enhancements

Potential improvements to consider:

1. **Add More Providers**: OpenAI, Azure OpenAI, AWS Bedrock, Cohere
2. **Custom OpenCode Commands**: Create project-specific commands in `programs.opencode.commands`
3. **Custom OpenCode Agents**: Define specialized agents in `programs.opencode.agents`
4. **OpenCode Rules**: Add global instructions via `programs.opencode.rules`
5. **Model Presets**: Create task-specific model configurations
6. **Integration Scripts**: Shell scripts to quickly switch between providers
7. **Cost Tracking**: Monitor API usage across providers
8. **Performance Benchmarks**: Compare response quality and speed across providers
