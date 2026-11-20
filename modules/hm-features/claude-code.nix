{inputs, ...}: {
  hmModules.features.claude-code = {
    config,
    lib,
    pkgs,
    ...
  }: let
    claudeCodePkg = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

    # Skill libraries and helper binaries — see myLib/agent-skills.nix for how
    # each set is enumerated and why.
    skills = import ../../myLib/agent-skills.nix {inherit lib pkgs inputs;};
    agentBrowserPkg = skills.agent-browser;

    # `m365claude`: regular Claude with the Microsoft 365 MCP merged in for that
    # session only (via --mcp-config, which adds to — not replaces — the normal
    # servers). It has to stay out of the always-on servers: all 336 of its tools
    # cost 741K context tokens against a 42K zero-server floor — 74% of the 1M
    # window, gone before the first prompt. `--enabled-tools` is a regex over tool
    # names; measured costs are mail 106K, mail|calendar 170K, +contact 196K, so
    # the default stays at the one surface that has ever actually been called.
    # Benchmark: `claude -p 'say ok' --mcp-config <cfg> --strict-mcp-config`, then
    # read the first request's usage out of the session transcript.
    m365McpConfig = pkgs.writeText "ms365-mcp.json" (builtins.toJSON {
      mcpServers.ms365 = {
        command = "${pkgs.nodejs}/bin/npx";
        args = [
          "-y"
          "@softeria/ms-365-mcp-server"
          "--org-mode"
          "--enabled-tools"
          cfg.ms365.enabledTools
        ];
      };
    });
    m365ClaudePkg = pkgs.writeShellScriptBin "m365claude" ''
      exec ${claudeCodePkg}/bin/claude --mcp-config ${m365McpConfig} "$@"
    '';

    cfg = config.myHomeManager.claude-code;

    # `claude` wrapper: point Claude Code at the cli-proxy-api pool on luna
    # (myLib/claude-pool.nix) so requests are spread over the pooled Claude
    # accounts instead of the single OAuth login in ~/.claude. The proxy
    # authenticates upstream with its own stored tokens, so what Claude Code
    # sends is the pool's api key — ANTHROPIC_API_KEY is cleared so it can't
    # fall back to a real Anthropic key. hiPrio to win over the raw claude-code
    # binary the development bundle installs.
    #
    # The key rides in x-api-key rather than ANTHROPIC_AUTH_TOKEN whenever
    # ~/.claude holds a live claude.ai login: an auth token outranks that
    # login, and /voice only exists while the login is the winning auth (its
    # speech-to-text goes straight to Anthropic, never through the base URL,
    # and costs no usage). The OAuth bearer still lands in Authorization, which
    # CPA just doesn't match; it accepts a request when any of Authorization,
    # x-api-key, x-goog-api-key or ?key= holds a configured key
    # (internal/access/config_access/provider.go). Without a login, or with a
    # refresh token past its expiry, Claude Code refuses to start rather than
    # use the base URL, so that case keeps the auth token.
    # Falls back to Claude Code's own OAuth whenever the pool can't be reached
    # (luna down, op-secrets not rendered yet): silently routing at that point
    # would break `claude` entirely rather than degrade.
    pool = import ../../myLib/claude-pool.nix;
    claudePoolPkg = lib.hiPrio (pkgs.writeShellScriptBin "claude" ''
      keyfile=${pool.apiKeyFile}

      if [ -r "$keyfile" ] && [ -s "$keyfile" ] &&
         timeout 2 bash -c '</dev/tcp/${pool.host}/443' 2>/dev/null; then
        export ANTHROPIC_BASE_URL="${pool.url}"
        # Must be empty, not unset: a real key here would let Claude Code bill
        # the API directly instead of going through the pooled subscriptions.
        export ANTHROPIC_API_KEY=""
        if ${lib.getExe pkgs.jq} -e --argjson now "$(date +%s000)" \
             '.claudeAiOauth.refreshToken and ((.claudeAiOauth.refreshTokenExpiresAt // $now + 1) > $now)' \
             "$HOME/.claude/.credentials.json" >/dev/null 2>&1; then
          unset ANTHROPIC_AUTH_TOKEN
          export ANTHROPIC_CUSTOM_HEADERS="x-api-key: $(cat "$keyfile")"
        else
          unset ANTHROPIC_CUSTOM_HEADERS
          export ANTHROPIC_AUTH_TOKEN="$(cat "$keyfile")"
          # claude.ai cloud connectors need the OAuth login to be the winning
          # auth source, which an auth token never lets it be. Left alone,
          # Claude Code notices that and nags every session; opting out
          # explicitly makes it skip the fetch instead of warning about it.
          export ENABLE_CLAUDEAI_MCP_SERVERS=0
          # Without a claude.ai login Claude Code drops to the API-key default
          # of a 5m prompt cache; a subscriber gets 1h on the main thread. This
          # restores that, and only that: subagents read
          # CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL and stay at 5m, as natively.
          # The proxy passes a native client's cache_control through untouched.
          export CLAUDE_CODE_PROMPT_CACHE_TTL=1h
        fi
      else
        # Drop any inherited routing so "fallback" really means direct — a
        # stale ANTHROPIC_BASE_URL in the shell (or a nested claude session)
        # would otherwise silently survive into the fallback path. Connectors
        # do work on this path, so the opt-out goes too.
        unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_CUSTOM_HEADERS ENABLE_CLAUDEAI_MCP_SERVERS

        if [ ! -r "$keyfile" ]; then
          echo "claude: cannot read $keyfile — using the direct OAuth login." >&2
          echo "        needs op-secrets.service and the onepassword-secrets group (re-login after first deploy)." >&2
        else
          echo "claude: ${pool.host} unreachable — using the direct OAuth login." >&2
        fi
      fi

      exec ${claudeCodePkg}/bin/claude "$@"
    '');

    globalClaudeMd = builtins.readFile ./global-agent-instructions.md;

    # Keys we own inside ~/.claude/settings.json. The file can't be a
    # home.file symlink: Claude Code writes to it itself (/model, /theme), so
    # these get deep-merged in on every activation and everything else in the
    # file is left alone.
    declaredSettingsAttrs = {
      # Empty string hides the Co-Authored-By trailer / "Generated with"
      # footer entirely. The global instructions already forbid attribution,
      # but the harness injects its own default, so it has to die at the source.
      attribution = {
        commit = "";
        pr = "";
      };
      # Also gates idle compaction, so this one key turns off every automatic
      # compact. Manual /compact still works (DISABLE_COMPACT would kill that too).
      autoCompactEnabled = false;
      # MCP connect timeout, default 30s. On luna, with agents' builds holding
      # load at 40-50 on 8 cores, three node servers starting in parallel inside
      # an agent's cgroup measured 35-46s, so every one of them dropped with
      # CONNECT_TIMEOUT. Servers connect in the background either way, so a
      # slow one costs nothing until its tools are called.
      env.MCP_TIMEOUT = "120000";
    };
    declaredSettings = (pkgs.formats.json {}).generate "claude-declared-settings.json" declaredSettingsAttrs;

    # Claude Code on this machine's defenestrate Windows (`windows.enable`).
    # Its logon task copies these from here into %USERPROFILE%\.claude
    # (wsl.linux.files in hosts/<host>/windows.nix), next to the pool key
    # it copies from op-secrets' render. Paths are relative to $HOME.
    windowsDir = ".local/share/defenestrate/claude";
    windowsSettings = lib.recursiveUpdate declaredSettingsAttrs {
      # The wrapper's routing, minus its two fallbacks: an apiKeyHelper
      # outranks a claude.ai login, so the pool always wins (no /voice), and
      # with luna down this Claude fails rather than going direct. Both would
      # need a wrapper on Windows; the helper is enough to get going.
      # Absolute, with forward slashes and no $: Claude Code runs the helper
      # through whatever shell it finds (cmd, PowerShell or Git Bash), which
      # all take this the same way.
      apiKeyHelper = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:/Users/${config.home.username}/.claude/pool-key.ps1";
      # The bypass-permissions warning: it's run with
      # --dangerously-skip-permissions at logon with nobody to click
      # through it (Linux's settings.json only has it because Claude wrote
      # it there itself; 2026-11-20).
      skipDangerousModePermissionPrompt = true;
      env = {
        ANTHROPIC_BASE_URL = pool.url;
        ANTHROPIC_API_KEY = "";
        # As the wrapper's no-login branch, which is what this always is.
        ENABLE_CLAUDEAI_MCP_SERVERS = "0";
        CLAUDE_CODE_PROMPT_CACHE_TTL = "1h";
        # home.sessionVariables below, which Windows has no shell to read.
        CLAUDE_CODE_RETRY_WATCHDOG = "1";
        CLAUDE_CODE_FORK_SUBAGENT = "0";
      };
    };
    # Run by the defenestrate shell's autostart at each Windows logon while
    # a test plan is set (modules/flake/windows.nix): Claude Code as a
    # testing subagent of the Linux session that rebooted into Windows. It
    # waits for the logon task's copies (pool key, plan, this state) and, on
    # a fresh install, for winget to put claude on PATH, which lands after
    # the console started, so PATH is reread from the registry.
    windowsStartTests = ''
      $claude = Join-Path $env:USERPROFILE '.claude'
      Write-Host 'Waiting for the logon task to copy Claude config from Linux (wsl.log) and for winget to install Claude Code (apps.log), both in %LOCALAPPDATA%\defenestrate'
      # This logon's copies, not the last boot's: the logon task writes
      # linux-files.txt after copying, and an older plan left from the boot
      # before once got tested instead of the new one (2026-11-20).
      $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
      $copied = Join-Path $env:LOCALAPPDATA 'defenestrate\linux-files.txt'
      while (-not ((Test-Path $copied) -and (Get-Item $copied).LastWriteTime -gt $boot -and (Test-Path "$claude\pool-key") -and (Test-Path "$claude\defenestrate-tests.md") -and (Test-Path "$claude\claude-state.json") -and (Get-Command claude -ErrorAction SilentlyContinue))) {
          Start-Sleep 5
          $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
      }

      # Nested objects merge, everything else is replaced.
      function Merge($into, $from) {
          foreach ($p in $from.PSObject.Properties) {
              $have = $into.PSObject.Properties[$p.Name]
              if ($have -and $have.Value -is [pscustomobject] -and $p.Value -is [pscustomobject]) {
                  Merge $have.Value $p.Value
              } else {
                  $into | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
              }
          }
      }
      $json = Join-Path $env:USERPROFILE '.claude.json'
      $state = [pscustomobject]@{}
      if (Test-Path $json) {
          try { $state = Get-Content -Raw -LiteralPath $json | ConvertFrom-Json } catch { Write-Host "~/.claude.json isn't JSON, leaving it: $_" }
      }
      Merge $state (Get-Content -Raw -LiteralPath "$claude\claude-state.json" | ConvertFrom-Json)
      # No BOM: Windows PowerShell's UTF8 adds one.
      [IO.File]::WriteAllText($json, ($state | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding $false))

      $prompt = @'
      You're the testing half of a Linux Claude Code session that rebooted saturn into this Windows to test defenestrate. Nobody may be at the screen: never wait for an answer. Work through ~/.claude/defenestrate-tests.md, checking what you can yourself, including driving the UI (PowerShell with UI Automation, SendInput, screenshots), and mark what only a person could judge as not checked. Then follow its Last step, which hands back to Linux.
      '@
      Set-Location $env:USERPROFILE
      claude --dangerously-skip-permissions $prompt.Trim()
    '';
    # The test run's last step, a script rather than Claude's judgement:
    # twice the handoff was "done" with the file never renamed. Over \\wsl$
    # only creating new files has been reliable (renames silently don't
    # happen, appends are unproven), so the report is kept on NTFS and
    # copied over as a new file, with the Windows-side logs and every
    # Claude transcript here, which explain a run that ended early. The
    # rename happens inside WSL, and the reboot only once it's checked.
    windowsHandBack = ''
      param([Parameter(Mandatory = $true)][string]$Report)
      $ErrorActionPreference = 'Continue'
      $wsl = Join-Path $env:ProgramFiles 'WSL\wsl.exe'
      $linuxHome = '${config.home.homeDirectory}'
      $share = "\\wsl$\defenestrate\linux$($linuxHome -replace '/', '\')"
      $name = [IO.Path]::GetFileNameWithoutExtension($Report)
      $reports = "$share\.local\share\defenestrate\reports"
      $media = "$reports\$name-media"
      New-Item -ItemType Directory -Force -Path "$media\logs", "$media\transcripts" | Out-Null
      Copy-Item -LiteralPath $Report -Destination "$reports\$name.md" -Force
      $localMedia = Join-Path (Split-Path -Parent $Report) "$name-media"
      if (Test-Path -LiteralPath $localMedia) { Copy-Item -Path "$localMedia\*" -Destination $media -Recurse -Force }
      Copy-Item -Path "$env:LOCALAPPDATA\defenestrate\*.log", "$env:ProgramData\defenestrate\*.log" -Destination "$media\logs" -Force -ErrorAction SilentlyContinue
      Get-ChildItem "$env:USERPROFILE\.claude\projects" -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | Copy-Item -Destination "$media\transcripts" -Force

      $next = "$linuxHome/.local/state/next-boot"
      $out = @("pending before:") + (& $wsl -d defenestrate --cd / --exec /bin/busybox ls -ln "/linux$next" 2>&1)
      $pending = Test-Path "$share\.local\state\next-boot\claude-resume.pending"
      if ($pending) {
          $out += & $wsl -d defenestrate --cd / --exec /bin/busybox mv "/linux$next/claude-resume.pending" "/linux$next/claude-resume" 2>&1
          $out += @("after:") + (& $wsl -d defenestrate --cd / --exec /bin/busybox ls -ln "/linux$next" 2>&1)
      } else {
          $out += 'no claude-resume.pending: nobody is waiting'
      }
      & $wsl -d defenestrate --cd / --exec /bin/busybox test -e "/linux$next/claude-resume"
      $handedOver = $LASTEXITCODE -eq 0
      $out += "handed over: $handedOver"
      $out | ForEach-Object { "$_" } | Set-Content -LiteralPath "$media\handoff.txt"
      $out | ForEach-Object { Write-Host $_ }
      if ($pending -and -not $handedOver) {
          Write-Host 'The handoff file was not renamed; not rebooting, so someone can look.'
          exit 1
      }
      schtasks.exe /run /tn defenestrate-reboot-to-linux
    '';
    # The NixOS-specific sections swapped for Windows ones; the rest is the
    # same instructions.
    windowsClaudeMd = let
      rest = lib.last (lib.splitString "## Git and GitHub" globalClaudeMd);
    in ''
      # Global Claude Code Instructions

      ## System Info

      This is the Windows side of a dual-boot machine, built by defenestrate
      (github.com/cramt/defenestrate): explorer.exe is replaced by its tiling
      shell. The other side is NixOS. Both are declared in nixconf: Windows in
      hosts/<host>/windows.nix (winget apps, registry, files copied from Linux at
      logon), and this file and settings.json come from the Linux config, so
      edits made here are overwritten at the next logon.

      ${lib.optionalString (cfg.windows.testPlan != null) ''
        ## Testing defenestrate

        `~/.claude/defenestrate-tests.md` is the checklist for verifying the
        latest defenestrate build on this machine. When Alex asks you to test,
        verify or check defenestrate (or "the boot"), work through it and write
        the report where it says.

      ''}## Installing packages

      - winget. Anything that should stay goes into `apps` in the host's
        windows.nix too, or the next reflash loses it

      ## Git and GitHub${lib.replaceStrings ["wl-copy it" "`| wl-copy`" "- The gh cli is available and authed\n"] ["copy it with Set-Clipboard" "`| Set-Clipboard`" ""] rest}'';
    # User-scope MCP servers live in ~/.claude.json, which Claude Code rewrites
    # constantly (project state, counters), so same deal: these keys get merged
    # in, any server not named here is left alone. Store paths rather than
    # `npx -y`: npx resolved the package on every launch (context7 measured
    # 13.5s to initialize vs 6-7s from the store), and it fetched playwright
    # and chrome-devtools builds that look for Google Chrome in /opt.
    declaredClaudeJson = (pkgs.formats.json {}).generate "claude-declared-mcp.json" {
      mcpServers = {
        # nixpkgs' playwright-mcp is linked against the playwright that
        # matches playwright-driver.browsers and defaults to its chromium, so
        # no executable path is needed. Headless because the agent is the only
        # one looking; isolated (fresh profile per session) is the wrapper's
        # default. The old `--extension` mode drove a Chrome extension, and
        # the daily browser is Zen.
        playwright = {
          command = lib.getExe pkgs.playwright-mcp;
          args = ["--headless"];
        };
        chrome-devtools = {
          command = lib.getExe pkgs.chrome-devtools-mcp;
          args = ["--headless" "--isolated" "--no-usage-statistics" "--no-performance-crux"];
        };
        context7 = {
          command = lib.getExe pkgs.context7-mcp;
          args = [];
        };
      };
    };
    mergeJson = file: declared: ''
      f=${file}
      install -d "$(dirname "$f")"
      # Refuse to clobber a file we can't parse — that's hand-edited state
      # worth more than our few keys.
      if [ -e "$f" ]; then
        current=$(jq . "$f") || { echo "claude-merge-settings: $f is not valid JSON, skipping" >&2; exit 0; }
      else
        current='{}'
      fi
      printf '%s' "$current" | jq --slurpfile declared ${declared} '. * $declared[0]' > "$f.new"
      mv "$f.new" "$f"
    '';
    mergeSettings = pkgs.writeShellApplication {
      name = "claude-merge-settings";
      runtimeInputs = [pkgs.coreutils pkgs.jq];
      text = ''
        (${mergeJson ''"$HOME/.claude/settings.json"'' declaredSettings})
        (${mergeJson ''"$HOME/.claude.json"'' declaredClaudeJson})
      '';
    };
  in {
    options.myHomeManager.claude-code = {
      enable = lib.mkEnableOption "myHomeManager.claude-code";
      agent-browser.enable =
        lib.mkEnableOption "Vercel agent-browser CLI + Claude Code skill"
        // {default = true;};
      pstack.enable =
        lib.mkEnableOption "vendored pstack judgment skills (unslop, type-system-discipline, technical-writing, …)"
        // {default = true;};
      mattpocock.enable =
        lib.mkEnableOption "mattpocock/skills engineering-process library (spec → tickets → triage → implement → review)"
        // {default = true;};
      ms365.enable =
        lib.mkEnableOption "`m365claude` launcher (regular Claude + Microsoft 365 MCP). Kept out of the always-on servers because its 336 tool schemas cost 741K context tokens per session"
        // {default = true;};
      ms365.enabledTools = lib.mkOption {
        type = lib.types.str;
        default = "mail";
        example = "mail|excel|todo";
        description = "Regex handed to ms-365-mcp-server --enabled-tools, narrowing which of its 336 tools reach the context.";
      };
      rea.enable =
        lib.mkEnableOption "REA reverse-engineering skill + `rea` CLI (with Ghidra)"
        // {default = true;};
      dm-me.enable =
        lib.mkEnableOption "Discord DM-to-Alex skill + `dm-me` CLI (yelliv bot)"
        // {default = true;};
      mtg.enable =
        lib.mkEnableOption "MTG skills (general + Commander) + `scryfall` bulk-data CLI and `gauntlet`"
        // {default = true;};
      # Off by default: it needs the m365Account secret, which only hosts that
      # render it (mars) have.
      windows.enable = lib.mkEnableOption "Claude Code config for this machine's defenestrate Windows, under ~/${windowsDir} for its logon task to copy over (hosts/<host>/windows.nix)";
      windows.testPlan = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "A checklist for Claude on Windows to verify a defenestrate build with, copied over as ~/.claude/defenestrate-tests.md and named in its CLAUDE.md.";
      };
      outlook.enable = lib.mkEnableOption "Outlook web mail skill + `outlook-browser` CLI (work mailbox via agent-browser)";
      agents = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.str;
              description = "When the main agent should delegate here; Claude Code routes on it.";
            };
            model = lib.mkOption {
              type = lib.types.str;
              description = "Anything `--model` takes, including a pool model id like `m365/gpt-5.5[1m]`.";
            };
            prompt = lib.mkOption {
              type = lib.types.str;
              description = "The subagent's system prompt.";
            };
          };
        });
        default = {};
        description = "Subagents, rendered to ~/.claude/agents/<name>.md.";
      };
    };
    config = lib.mkIf cfg.enable (lib.mkMerge [
      (lib.mkIf cfg.windows.enable {
        home.file = {
          "${windowsDir}/settings.json".source = (pkgs.formats.json {}).generate "claude-windows-settings.json" windowsSettings;
          "${windowsDir}/CLAUDE.md".text = windowsClaudeMd;
          # Trimmed: whether op leaves a newline on the render isn't
          # something to depend on in a header value.
          "${windowsDir}/defenestrate-tests.md" = lib.mkIf (cfg.windows.testPlan != null) {source = cfg.windows.testPlan;};
          # What Claude Code's first run asks a person for (theme, trusting
          # the home folder, the bypass-permissions warning), answered up
          # front so the test run needs nobody at the keyboard. Merged into
          # ~/.claude.json by start-tests.ps1, never copied over it: Claude
          # Code keeps its own state in there.
          "${windowsDir}/claude-state.json".source = (pkgs.formats.json {}).generate "claude-windows-state.json" {
            hasCompletedOnboarding = true;
            theme = declaredSettingsAttrs.theme or "dark";
            bypassPermissionsModeAccepted = true;
            # Forward slashes: how Claude Code keys Windows paths (seen
            # 2026-11-20).
            projects."C:/Users/${config.home.username}" = {
              hasTrustDialogAccepted = true;
              hasCompletedProjectOnboarding = true;
            };
          };
          "${windowsDir}/start-tests.ps1" = lib.mkIf (cfg.windows.testPlan != null) {text = windowsStartTests;};
          "${windowsDir}/hand-back.ps1" = lib.mkIf (cfg.windows.testPlan != null) {text = windowsHandBack;};
          "${windowsDir}/pool-key.ps1".text = ''
            (Get-Content -Raw -LiteralPath "$env:USERPROFILE\.claude\pool-key").Trim()
          '';
          # Git for Windows (there for Claude Code's Bash tool) refuses repos on
          # the WSL share as "dubious ownership": their owner is a Linux uid it
          # can't map. %(prefix)/// is how it spells a UNC path; the share is
          # defenestrate's WSL distro with the Linux install mounted at /linux.
          # Lands as %USERPROFILE%\.config\git\config, git's XDG global, so
          # ~/.gitconfig stays free for what git writes there itself.
          "${windowsDir}/gitconfig".text = ''
            [safe]
            	directory = %(prefix)///wsl$/defenestrate/linux${config.home.homeDirectory}/*
          '';
        };
      })
      {
        # Not for me, for the agent: it reaches for `python3 - <<'EOF'` to edit
        # files no matter what CLAUDE.md says. Without it, 147 of those calls
        # failed in a month of transcripts (2026-09-14..10-14, half of all
        # sessions), and a few chained ones failed silently and shipped the
        # unedited file, conflict markers included.
        home.packages =
          [claudePoolPkg pkgs.python3]
          ++ lib.optional cfg.ms365.enable m365ClaudePkg;

        # Sit out a rate limit instead of dying on it. Claude Code's default
        # 429 path gives up two ways: a retry-after longer than 60s is
        # rejected outright ("retry after too long"), and without one it
        # exhausts 10 exponential retries capped at 32s — measured at 11
        # attempts over 3m18s against a permanently-429ing upstream, which is
        # nothing next to a 5h window. This moves 429/overloaded onto the
        # persistent path: the attempt counter stops applying, backoff caps at
        # 5m instead of 32s, and anthropic-ratelimit-unified-reset is honoured
        # up to 6h. Verified against a fake upstream returning retry-after: 25
        # and recovering at 75s — four attempts spaced 25s apart, then the
        # turn completed.
        #
        # A session variable rather than an export in claudePoolPkg, because
        # the wrapper's fallback is the direct OAuth login, which hits the real
        # window just as hard, and `m365claude` skips the wrapper entirely.
        # t3code gets it from here too — it captures the environment through
        # `zsh -i -c` (see hm-features/zsh.nix) and hands process.env to the
        # CLI it spawns.
        #
        # Remove when upstream makes waiting the default for subscription
        # limits rather than something the runner opts into.
        home.sessionVariables.CLAUDE_CODE_RETRY_WATCHDOG = "1";

        # Kills the per-subagent progress summaries (the "Reading foo.ts" line
        # under a running agent, regenerated every 30s by a forked model call).
        # Interactive sessions only run them because the fork-subagent gate is
        # on; there's no dedicated switch (the served summary config has modes
        # full/short, no off). Side effect: subagent_type "fork" goes away too.
        # Measured on 2.1.312 with two tmux sessions spawning the same subagent:
        # default logged [AgentSummary] for each agent, this logged none.
        # Remove if upstream ships a real setting for it.
        home.sessionVariables.CLAUDE_CODE_FORK_SUBAGENT = "0";

        home.activation.claude-settings = lib.hm.dag.entryAfter ["writeBoundary"] ''
          run ${lib.getExe mergeSettings}
        '';

        home.file =
          {
            ".claude/CLAUDE.md".text = globalClaudeMd;
            ".claude/skills/status".source = skills.status.path;
            ".claude/skills/write-like-alex".source = skills.write-like-alex.path;
            ".claude/skills/gm".source = skills.gm.path;
          }
          // lib.mapAttrs' (name: agent:
            lib.nameValuePair ".claude/agents/${name}.md" {
              text = ''
                ---
                name: ${builtins.toJSON name}
                description: ${builtins.toJSON agent.description}
                model: ${builtins.toJSON agent.model}
                ---

                ${agent.prompt}
              '';
            })
          cfg.agents;

        # M365 Copilot through the pool (cli-proxy-api on luna routes m365/ to
        # the M365 proxy). gpt-5.5-think-deeper because it's the proxy's best
        # measured tool-caller (26/30 on its bench); a caller can still pass
        # another m365/ model per Agent call.
        myHomeManager.claude-code.agents.m365 = {
          description = "General-purpose worker running on Microsoft 365 Copilot (GPT) instead of Claude. Use when asked to delegate to M365/Copilot/GPT, or to get a second opinion from a non-Claude model.";
          model = "m365/gpt-5.5-think-deeper[1m]";
          prompt = ''
            You are a general-purpose coding subagent. Do the task you were
            given with the tools you have, then report back concisely: what you
            did, what you found, and anything left undone. Run commands rather
            than guessing at their output.
          '';
        };
      }
      # Vercel agent-browser: the CLI is a self-contained native binary (no
      # `agent-browser install` needed — it's pointed at a nix Chromium and
      # serves its own version-matched skill content). The upstream SKILL.md is
      # just a discovery stub telling the agent to run `agent-browser skills get
      # core`, so we symlink it into every config dir the three claude variants
      # use.
      (lib.mkIf cfg.agent-browser.enable (let
        skillStub = "${agentBrowserPkg}/share/agent-browser/skills/agent-browser/SKILL.md";
      in {
        home.packages = [agentBrowserPkg];
        home.file.".claude/skills/agent-browser/SKILL.md".source = skillStub;
      }))
      (lib.mkIf cfg.outlook.enable {
        home.packages = [skills.outlook-browser];
        home.file.".claude/skills/outlook/SKILL.md".source = skills.outlook.path;
      })
      (lib.mkIf cfg.dm-me.enable {
        home.packages = [skills.dm-me-bin];
        home.file.".claude/skills/dm-me/SKILL.md".source = skills.dm-me.path;
      })
      # CLI rather than MCP server, so the skill costs only its description
      # instead of 207 tool schemas (75K tokens) in every session.
      (lib.mkIf cfg.rea.enable {
        home.packages = [pkgs.rea-agents];
        home.file.".claude/skills/reverse-engineer-anything".source = pkgs.rea-agents.skill;
      })
      (lib.mkIf cfg.mtg.enable {
        home.packages = [skills.scryfall skills.gauntlet skills.mtg-lore];
        home.file = {
          ".claude/skills/mtg/SKILL.md".source = skills.mtg.path;
          ".claude/skills/mtg-commander".source = skills.mtg-commander.path;
        };
      })
      # pstack + mattpocock: symlink each skill dir in. Skills-only installs — no
      # plugin registration, no SessionStart hook — so they stay as declarative
      # and disposable as the agent-browser stub above.
      (lib.mkIf cfg.pstack.enable {
        home.file = lib.mkMerge (map (skill: {
            ".claude/skills/${skill.name}".source = skill.path;
          })
          skills.pstack);
      })
      (lib.mkIf cfg.mattpocock.enable {
        home.file = lib.mkMerge (map (skill: {
            ".claude/skills/${skill.name}".source = skill.path;
          })
          skills.mattpocock);
      })
    ]);
  };
}
