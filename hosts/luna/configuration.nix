{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    inputs.disko.nixosModules.default
    (import ./disko.nix {device = "/dev/disk/by-id/ata-Samsung_SSD_850_EVO_250GB_S2R4NB0J105220R";})
  ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  security.polkit.enable = true;

  # T3 Code checks out git worktrees under ~/.t3, each carrying a multi-GB Rust
  # `target/` (one Windows cross-compile target alone hit 67G) — that filled
  # luna's 228G root. Relocate the bytes to /pool (5.3T) with a bind mount, NOT
  # a symlink: Claude Code keys its session transcripts (~/.claude/projects/<enc>)
  # by the *realpath* of the agent's cwd, and a symlink would resolve ~/.t3 →
  # /pool, changing that key and orphaning every existing agent's history. A bind
  # mount is transparent to realpath, so ~/.t3 stays canonical while the data
  # lives on /pool/t3code.
  fileSystems."/home/cramt/.t3" = {
    device = "/pool/t3code";
    fsType = "none";
    options = ["bind"];
    depends = ["/pool"];
  };

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;

  programs.hyprland = {
    enable = false;
    withUWSM = false;
  };

  myNixOS = {
    # Agents act as the bot by default; cramt is there for anything that has to
    # be done as Alex (`gh auth switch`, or pinned in T3 Code's settings).
    gh-accounts = {
      enable = true;
      active = {
        login = "solemn-simulacrum";
        tokenReference = "op://Homelab/GitHub/solemnSimulacrumToken";
      };
      others.cramt = "op://Homelab/GitHub/cramtToken";
    };
    services.m365-copilot-proxy.enable = true;
    gnupg.enable = true;
    nvidia.enable = true;
    docker = {
      enable = true;
      httpPort = 2375;
    };
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/artemis2_1.jpg;
    bundles.users.enable = true;

    services = {
      # T3 Code server: offload coding-agent work to luna from the mars/saturn
      # desktop app. Runs as cramt so agents get git/ssh + the agent CLIs
      # (dev bundle). At t3.<domain> the passkey is the only login; LAN
      # clients (the desktop app) pair with `just t3_pair`.
      t3code = {
        enable = true;
        user = "cramt";
        subdomain = "t3";
        # <port>.t3.<domain> for "open in system browser" on a preview.
        portsSubdomain = "t3";
        # Headless: no 1Password agent here, so agents need the key on disk.
        onDiskSshKey.enable = true;
        # Agents can `just deploy luna` (the Justfile moves the run out of
        # the t3code unit, which the activation may restart).
        selfDeploy.enable = true;
      };
      nixarr.enable = true;
      # Kobl host runner. Home on /pool: jobs clone repos and build in there.
      koblet = {
        enable = true;
        stateDir = "/pool/koblet";
      };
      # Passkey portal for the owner-only vhosts (caddy serviceMap forward-auth).
      authelia = {
        enable = true;
        # Plaintext lives in op://Homelab/Authelia/password; only needed to
        # enroll a passkey on a new device.
        user.hashedPassword = "$argon2id$v=19$m=65536,t=3,p=4$fT170oQb3iDhmNYoqCpTZA$80k++XmJ8d5NRibh16c7CZXOwTHnemn3IZDIoFj2SS0";
      };
      recyclarr.enable = true;
      cleanuparr = {
        enable = true;
        dataVolume = "/pool/configs/cleanuparr";
      };
      # Fleet metrics land here: luna is the always-on host and the only one
      # running caddy, which is what the roaming agents push through.
      metrics.server = {
        enable = true;
        # 200GB of TSDB has no business on the 228G root SSD, and /pool is
        # where every other data-heavy service on this box already lives.
        dataDir = "/pool/prometheus";
        dataDirDepends = ["/pool"];
        # bcrypt from `caddy hash-password`; the plaintext lives in
        # op://Homelab/Metrics/remoteWritePassword and reaches agents via opnix.
        auth.hashedPassword = "$2a$14$np6mAmdVPkGBrPrFnV4rSeUw45WaHHvVngHupMyOSyClwwnL7444a";
      };
      # The insight driver is a user unit, so it can't declare this itself.
      metrics.textfiles.insight-driver = "${config.home-manager.users.cramt.myHomeManager.insight-driver.stateDir}/metrics.prom";
      # Dashboards over the above at grafana.<domain>, behind the passkey.
      grafana.enable = true;
      # Prometheus alerts as Discord DMs from yelliv.
      alerts.enable = true;
      garage.enable = false;
      btopttyd.enable = false;
      minecraft-forge = {
        enable = false;
        url = "https://www.curseforge.com/minecraft/modpacks/nomi-ceu";
        dataDir = "/pool/minecraft-forge";
      };
      # Tailnet coordinator at hs.<domain>; luna is also a node, like every host.
      headscale.enable = true;
      caddy = {
        enable = true;
        cacheVolume = "/pool/configs/caddy-cache";
        staticFileVolumes = {};
      };
      # cramt's Claude pool at cliproxy.<domain>: panel behind the passkey, /v1
      # behind the shared API key. Every host's `claude` points here.
      cli-proxy-api.enable = true;
      # Speech-to-text on the 1660: Bazarr's fallback when no provider has
      # subtitles that match a dub.
      whisper.subtitles.enable = true;
      foundryvtt = {
        enable = false;
        dataVolume = "/pool/configs/foundryvtt_a";
      };
      homelab_system_controller = {
        enable = false;
        databaseUrl = "sqlite:/pool/homelab_discord_bot.db?mode=rwc";
      };
      open-webui.enable = false;
      postgres = {
        dataDir = "/pool/pgsql";
      };
      terraform_remote_backend.enable = true;
      servatrice.enable = true;
      sshd.enable = true;
    };
  };

  networking.networkmanager.enable = true;

  networking.interfaces.enp3s0.wakeOnLan = {
    policy = ["magic"];
    enable = true;
  };

  programs.nix-ld.enable = true;

  # Configure keymap in X11
  # The T3 Code server's own settings (myNixOS.services.t3code above is the
  # fleet wiring: port, vhost, secrets).
  services.t3code = {
    # Device panel + agent access, tools from the store. No Android SDK
    # here, so its sources are remote ones: SSH device hosts, EAS, Simlock.
    devices = {
      enable = true;
      simlock.enable = true;
    };
    # codex ships enabled in t3code, but there's no codex CLI to run.
    providers.codex = false;
    # Dictation for every client paired to luna, on the 1660 over Vulkan
    # (about 2s per 11s of speech, against 9s on the CPU). Pinned from the
    # store so a fresh ~/.t3 doesn't sit on a 700 MB download first.
    speech.model = "handy-computer/parakeet-unified-en-0.6b-gguf";
    # Daily look at upstream's voice work against Alex's relay-call design
    # (discussion 22091), DMing only when something moved. Drop it once
    # thread calls ship for non-Codex providers.
    scheduledTasks.voice-watch = {
      title = "t3code voice watch";
      project = "/pool/dev/nixconf";
      schedule.daily.timeOfDay = "09:00";
      model.model = "claude-sonnet-5-5";
      prompt = ''
        Watch pingdotgg/t3code for progress toward Alex's voice-call design
        (https://github.com/pingdotgg/t3code/discussions/22091#discussioncomment-19395387):
        a relay-style call on any thread, with VAD, send or steer, the reply read
        back aloud, working with the screen locked, provider-agnostic, and STT/TTS
        on-device or OpenAI-compatible. This is read-only research: change nothing
        in this repo, and post nothing on GitHub.

        1. Read ~/.local/state/t3code-voice-watch/state.md, the last state seen.
        2. Collect the current state with gh:
           - PR 29394 (Codex voice conversations): state, draft, head sha,
             updatedAt, new commits and review comments since the recorded sha.
           - Open and recently merged PRs about voice, dictation, speech,
             transcription, TTS or realtime (gh search prs -R pingdotgg/t3code).
           - Discussion 22091: comment count and any new comments
             (gh api graphql).
           - On main: the kinds in VoiceTranscriptionDestination
             (packages/contracts/src/settings.ts), and whether a voice/call
             session contract exists and what kinds it takes.
        3. Compare with state.md. Substantive changes: a PR opened, merged or
           closed; new commits or reviews on a tracked PR; a new
           transcription or TTS backend; a call or session contract that
           gains a non-Codex or relay kind; new comments on 22091. A bumped
           updatedAt with nothing behind it doesn't count.
        4. On substantive change, send a single DM with `dm-me "<message>"`:
           a few short lines in plain language on what changed and how close
           it brings the design, with PR links. Stay quiet otherwise.
        5. Always rewrite state.md with what you saw today, keeping its format.
      '';
    };
    # M365 Copilot's GPT and Claude models, through Claude Code against
    # the cli-proxy-api pool, which routes the m365/ prefix to the proxy.
    # [1m] is the proxy's real window (its /v1/models says 1M); Claude
    # Code strips it before the request, and without it assumes 200k for
    # a model it doesn't know and compacts there.
    customModels.claudeAgent =
      map (model: {
        slug = "m365/${model}[1m]";
        name = "${model} (M365)";
      })
      config.myNixOS.services.m365-copilot-proxy.models;
  };

  services.xserver = {
    xkb = {
      variant = "nodeadkeys";
      layout = "dk";
    };
  };

  # Configure console keymap
  console.keyMap = "dk-latin1";

  # `just on=luna deploy` builds the whole fleet here, eros's aarch64 bits included.
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  nix.settings = let
    caches = ["https://cache.nixos.org/" "http://192.168.0.107:5000/" "http://192.168.0.106:5000/"];
  in {
    # this doesnt work when the hosts arent available https://github.com/NixOS/nix/issues/6901
    # should only be using this strategy on the server
    # trusted-substituters = caches;
    # substituters = caches;
    experimental-features = ["nix-command" "flakes"];
    extra-platforms = config.boot.binfmt.emulatedSystems;
    # Build scratch off the 228G root: defenestrate's Windows ISO build alone
    # needs ~25G, and a failed one leaves / full for everything else.
    build-dir = "/pool/nix-build";
  };
  # Otherwise a late /pool mount sends builds to the bare mountpoint on /.
  systemd.services.nix-daemon.unitConfig.RequiresMountsFor = ["/pool"];
  environment.systemPackages = [
    pkgs.ghostty.terminfo
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # The btrfs migration left /pool, /pool/media/.state and .state/nixarr owned
  # by cramt while the service directories beneath them are root- or
  # service-owned. systemd-tmpfiles refuses to descend such a transition and
  # skips the rule while still exiting 0, so every nixarr rule under those
  # paths was silently ignored. Services predating the migration kept working
  # only because their directories already existed. nixarr documents this: a
  # stateDir whose parents are not root-owned is unsupported.
  #
  # `z` rather than `Z` -- adjust these three directories alone, never
  # recursing through the ~4TB of media beneath them.
  systemd.tmpfiles.rules = [
    "z /pool 0755 root root - -"
    "z /pool/media/.state 0755 root root - -"
    "z /pool/media/.state/nixarr 0755 root root - -"
    # Vivado (via gitlab:doronbehar/nix-xilinx) is tens of GB; keep it off root.
    "d /pool/Xilinx 0755 cramt users - -"
    "d /pool/nix-build 0755 root root - -"
  ];

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [8080]; # tmp
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # lg-b4-re first-boot (docs/first-boot.md Phase 1): slopbro/dangbro root the
  # TV over LAN by having it pull an HTTP payload back from this host. Default
  # inbound-deny was silently dropping those requests. LAN-only exposure, no
  # auth on that port while it's listening, but nothing listens on it outside
  # a rooting session. Remove once the B4 is rooted for good.
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?
}
