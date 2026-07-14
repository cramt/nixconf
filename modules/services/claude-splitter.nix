# Model-based splitter that sits in front of Claude Code's single ANTHROPIC_BASE_URL
# and branches on the request's `model` field:
#
#   * M365 slugs (gpt-5.5*, quick, claude-sonnet-4.5, ...) -> the local LiteLLM,
#     which translates to the M365 Copilot proxy (see modules/services/litellm.nix).
#   * everything else (real Claude model ids) -> api.anthropic.com *verbatim*,
#     forwarding the client's Authorization header untouched.
#
# That last part is the whole point: LiteLLM's unified /v1/messages endpoint
# always injects its OWN api key (x-api-key) and drops the client's Authorization,
# so routing Claude models through it forces API-key billing. Piping them straight
# to Anthropic keeps Claude Code's subscription OAuth intact — verified by capturing
# what reaches the backend. The Claude branch never touches LiteLLM, so M365/LiteLLM
# being down only affects the gpt-5.5 slugs, not normal Claude usage.
#
# Consumed by the `claude` wrapper in modules/hm-features/claude-code.nix, which
# points ANTHROPIC_BASE_URL here (and sets no auth token, so OAuth flows through).
{ ... }: {
  flake.nixosModules."services.claude-splitter" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.services.claude-splitter;
    port = config.port-selector.ports.claude-splitter;
    litellmPort = config.port-selector.ports.litellm;

    # Single source of truth for which models go to M365: derive the slug list
    # from LiteLLM's own model_list (the deployments backed by the local proxy,
    # i.e. hosted_vllm/*), so it can never drift from litellm.nix.
    m365Slugs = lib.unique (map (m: m.model_name)
      (lib.filter (m: lib.hasPrefix "hosted_vllm/" (m.litellm_params.model or ""))
        config.services.litellm.settings.model_list));
  in {
    options.myNixOS.services.claude-splitter.enable =
      lib.mkEnableOption "myNixOS.services.claude-splitter (needs myNixOS.services.litellm)";

    config = lib.mkIf cfg.enable {
      port-selector.auto-assign = [ "claude-splitter" ];

      systemd.services.claude-splitter = {
        description = "Model-based splitter in front of Claude Code (Anthropic passthrough + M365 via LiteLLM)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "litellm.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.nodejs}/bin/node ${./claude-splitter.mjs}";
          DynamicUser = true;
          Restart = "always";
          RestartSec = 2;
          Environment = [
            "SPLIT_PORT=${toString port}"
            "M365_SLUGS=${lib.concatStringsSep "," m365Slugs}"
            "LITELLM_URL=http://127.0.0.1:${toString litellmPort}"
            "ANTHROPIC_URL=https://api.anthropic.com"
          ];
        };
      };
    };
  };
}
