# whisper.cpp on luna's GPU, as two servers sharing one model file:
#
# - dictation: the OpenAI /v1/audio/transcriptions API on the LAN for voxtype
#   and anything else OpenAI-shaped. Vocabulary and the address live in
#   myLib/dictation.nix.
# - subtitles: transcribes whole episodes for Bazarr's whisperai provider,
#   behind whisper-asr-shim (Bazarr only speaks whisper-asr-webservice's API).
#
# CUDA by default: on a 5-minute clip of a dub, large-v3-turbo with beam 5
# took 58s on CUDA against 155s on Vulkan. The old reason for Vulkan, that CUDA
# meant compiling nvcc kernels on every nixpkgs bump, went away once
# cache.nixos-cuda.org (in modules/base/nixos-default.nix) started carrying
# whisper-cpp.
#
# No auth on either, so the dictation port is LAN-only (firewall, no caddy
# entry) and the subtitle servers bind to localhost.
{...}: {
  flake.nixosModules."services.whisper" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.whisper;
    dictation = import ../../myLib/dictation.nix;
    ports = config.port-selector.ports;

    package =
      {
        cuda = pkgs.whisper-cpp.override {cudaSupport = true;};
        vulkan = pkgs.whisper-cpp-vulkan;
      }
      .${cfg.backend};

    model = pkgs.fetchurl {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin";
      hash = "sha256-MX62nBFnPJ3h4fDUWbJTmZgE7HGsTCPBfs9fviTiWaE=";
    };

    # The first request after a start compiles the Vulkan pipelines (~20s), so
    # the unit pays that before it reports ready instead of the first request.
    warmupClip = pkgs.runCommand "whisper-warmup.wav" {} ''
      ${pkgs.sox}/bin/sox -n -r 16000 -c 1 -b 16 $out trim 0.0 1.0
    '';

    server = {
      name,
      host,
      port,
      inferencePath,
      args,
    }: {
      description = "whisper.cpp ${name} server";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      # NVIDIA keeps its compiled Vulkan pipelines here, which turns the warmup
      # into a cache hit after the first start.
      environment = lib.optionalAttrs (cfg.backend == "vulkan") {
        __GL_SHADER_DISK_CACHE_PATH = "/var/cache/whisper-${name}";
        __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
        XDG_CACHE_HOME = "/var/cache/whisper-${name}";
      };
      serviceConfig = {
        ExecStart = lib.escapeShellArgs ([
            "${package}/bin/whisper-server"
            "--model"
            model
            "--host"
            host
            "--port"
            (toString port)
            "--inference-path"
            inferencePath
          ]
          ++ args);
        ExecStartPost = lib.mkIf (cfg.backend == "vulkan") (pkgs.writeShellScript "whisper-${name}-warmup" ''
          until ${lib.getExe pkgs.curl} -sf -o /dev/null http://127.0.0.1:${toString port}/; do sleep 1; done
          ${lib.getExe pkgs.curl} -sf -o /dev/null \
            -F file=@${warmupClip} http://127.0.0.1:${toString port}${inferencePath}
        '');
        TimeoutStartSec = "3min";
        DynamicUser = true;
        SupplementaryGroups = ["render" "video"];
        CacheDirectory = "whisper-${name}";
        Restart = "on-failure";
      };
    };
  in {
    options.myNixOS.services.whisper = {
      backend = lib.mkOption {
        type = lib.types.enum ["cuda" "vulkan"];
        default = "cuda";
        description = "GPU backend whisper.cpp is built with.";
      };
      dictation = {
        enable = lib.mkEnableOption "the dictation server (OpenAI API, LAN)";
        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open the API port so the desktops can reach it.";
        };
      };
      subtitles = {
        enable = lib.mkEnableOption "the subtitle server Bazarr's whisperai provider talks to";
        port = lib.mkOption {
          type = lib.types.port;
          readOnly = true;
          # whisper-asr-webservice's port, which is also Bazarr's default
          # whisperai endpoint.
          default = 9000;
          description = "Port of the whisper-asr-webservice API, on localhost.";
        };
      };
    };

    config = lib.mkMerge [
      (lib.mkIf cfg.dictation.enable {
        port-selector.set-ports.${toString dictation.port} = "whisper";

        systemd.services.whisper = server {
          name = "dictation";
          host = "0.0.0.0";
          port = dictation.port;
          inferencePath = "/v1/audio/transcriptions";
          # Beam search (-bs 5) and no timestamps (-nt) were picked on a jargon
          # bench: beam fixed "luna", "deploy-rs" and "Ephemerate" for ~150ms,
          # and -nt stops segment breaks from showing up as newlines
          # mid-sentence.
          args = [
            "--language"
            "en"
            "--prompt"
            dictation.prompt
            "--beam-size"
            "5"
            "--no-timestamps"
          ];
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.dictation.openFirewall [dictation.port];
      })

      (lib.mkIf cfg.subtitles.enable {
        port-selector = {
          set-ports.${toString cfg.subtitles.port} = "whisper_asr_shim";
          auto-assign = ["whisper_subtitles"];
        };

        systemd.services.whisper-subtitles = server {
          name = "subtitles";
          host = "127.0.0.1";
          port = ports.whisper_subtitles;
          inferencePath = "/inference";
          # No prompt: the dictation vocabulary would only pull character
          # names towards MTG cards. Language comes per request from Bazarr.
          #
          # From a bench on 5 minutes of Witch Hat Atelier's dub:
          # - --max-context 0: carrying earlier text into each window looped
          #   "I'll be right back" six times over the music; without it the
          #   line appears once, cues get 10ms timing instead of whole
          #   seconds, and it ran faster (48s vs 58s).
          # - Beam 1 was only ~20% faster, not worth the worse text.
          # - No --vad: whisper.cpp 1.9.5's silero VAD dropped the first
          #   minute and the punctuation, and ran sentences together.
          args = [
            "--beam-size"
            "5"
            "--max-context"
            "0"
          ];
        };

        systemd.services.whisper-asr-shim = {
          description = "whisper-asr-webservice API for Bazarr, backed by whisper.cpp";
          wantedBy = ["multi-user.target"];
          wants = ["whisper-subtitles.service"];
          after = ["whisper-subtitles.service"];
          environment = {
            SHIM_LISTEN = "http://127.0.0.1:${toString cfg.subtitles.port}";
            WHISPER_URL = "http://127.0.0.1:${toString ports.whisper_subtitles}";
          };
          serviceConfig = {
            ExecStart = lib.getExe pkgs.whisper-asr-shim;
            DynamicUser = true;
            Restart = "on-failure";
          };
        };
      })
    ];
  };
}
