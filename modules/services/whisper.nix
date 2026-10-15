# Speech-to-text for the LAN: whisper.cpp's server with large-v3-turbo on the
# GPU, speaking the OpenAI /v1/audio/transcriptions API so voxtype (and anything
# else OpenAI-shaped) can use it. Vocabulary and the address live in
# myLib/dictation.nix.
#
# Vulkan rather than CUDA: on luna's GTX 1660 it is ~1.2s for a 4s clip, and
# the Vulkan build is in the binary cache while a CUDA one would compile nvcc
# kernels on every nixpkgs bump.
#
# Beam search (-bs 5) and no timestamps (-nt) were picked on a jargon bench:
# beam fixed "luna", "deploy-rs" and "Ephemerate" for ~150ms, and -nt stops
# segment breaks from showing up as newlines mid-sentence.
#
# No auth, so LAN only: there's no caddy entry, just the firewall port.
{...}: {
  flake.nixosModules."services.whisper" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.whisper;
    dictation = import ../../myLib/dictation.nix;

    model = pkgs.fetchurl {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin";
      hash = "sha256-MX62nBFnPJ3h4fDUWbJTmZgE7HGsTCPBfs9fviTiWaE=";
    };

    # The first request after a start compiles the Vulkan pipelines (~20s), so
    # the unit pays that before it reports ready instead of the first dictation.
    warmupClip = pkgs.runCommand "whisper-warmup.wav" {} ''
      ${pkgs.sox}/bin/sox -n -r 16000 -c 1 -b 16 $out trim 0.0 1.0
    '';
  in {
    options.myNixOS.services.whisper = {
      enable = lib.mkEnableOption "myNixOS.services.whisper";
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open the API port so the desktops can reach it.";
      };
    };

    config = lib.mkIf cfg.enable {
      port-selector.set-ports.${toString dictation.port} = "whisper";

      systemd.services.whisper = {
        description = "whisper.cpp speech-to-text server";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        environment = {
          # NVIDIA keeps its compiled-pipeline cache here, which turns the
          # warmup into a cache hit after the first start.
          __GL_SHADER_DISK_CACHE_PATH = "/var/cache/whisper";
          __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
          XDG_CACHE_HOME = "/var/cache/whisper";
        };
        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            "${pkgs.whisper-cpp-vulkan}/bin/whisper-server"
            "--model" model
            "--language" "en"
            "--prompt" dictation.prompt
            "--beam-size" "5"
            "--no-timestamps"
            "--host" "0.0.0.0"
            "--port" (toString dictation.port)
            "--inference-path" "/v1/audio/transcriptions"
          ];
          ExecStartPost = pkgs.writeShellScript "whisper-warmup" ''
            until ${lib.getExe pkgs.curl} -sf -o /dev/null http://127.0.0.1:${toString dictation.port}/; do sleep 1; done
            ${lib.getExe pkgs.curl} -sf -o /dev/null \
              -F file=@${warmupClip} http://127.0.0.1:${toString dictation.port}/v1/audio/transcriptions
          '';
          TimeoutStartSec = "3min";
          DynamicUser = true;
          SupplementaryGroups = ["render" "video"];
          CacheDirectory = "whisper";
          Restart = "on-failure";
        };
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [dictation.port];
    };
  };
}
