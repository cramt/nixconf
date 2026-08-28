# The employer's pooled Anthropic-shaped endpoint, shared by every coding agent
# that talks to it: opencode (modules/hm-features/opencode.nix), pi
# (modules/hm-features/pi.nix) and omp (modules/hm-features/omp.nix).
#
# Two fields on op://Homelab/OpenCode, which opnix renders as two files (a
# 1Password field can't hold a newline, so they can't share one envFile):
#
#   /var/lib/opnix/secrets/opencodeUrl      https://<host>/v1
#   /var/lib/opnix/secrets/opencodeApiKey   <key>
#
# Both stay out of the world-readable nix store — every consumer reads them at
# launch. The URL is stored *with* its /v1 because that is what opencode hands
# to its provider verbatim; the other two agents normalise it themselves (see
# their modules for which direction each needs).
#
# Lives in myLib/ rather than modules/ for the same reason agent-skills.nix
# does: import-tree turns every .nix file under modules/ into a flake-parts
# module, and this is a plain helper imported by relative path.
{lib}: let
  # The Claude models the pool serves. Every agent here has a maintained
  # built-in catalog entry for each of these (context window, pricing, thinking
  # levels), so only opencode — which enumerates its provider's models by hand —
  # needs the names; pi and omp resolve them from their own catalogs and pick up
  # upstream corrections for free.
  claudeModels = {
    "claude-opus-5" = "Claude Opus 5";
    "claude-opus-4-8" = "Claude Opus 4.8";
    "claude-opus-4-7" = "Claude Opus 4.7";
    "claude-opus-4-6" = "Claude Opus 4.6";
    "claude-sonnet-5" = "Claude Sonnet 5";
    "claude-fable-5" = "Claude Fable 5";
  };

  # The rest of the pool. These arrive over the same Anthropic-shaped endpoint,
  # so they get declared under the `anthropic` provider too — the pool does not
  # alias them onto claude-*, and no agent's catalog (nor models.dev) has an
  # entry to look them up from, so the limits have to be stated here.
  #
  # The pool does not advertise its real limits, so these are deliberate
  # under-estimates: too small only means the agent compacts earlier than it had
  # to, too large means a request the endpoint rejects outright. Raise one after
  # watching that model actually accept the larger window, not before.
  extraModels = {
    "gpt-5.6-luna" = {
      name = "GPT-5.6 Luna";
      contextWindow = 200000;
      maxTokens = 64000;
    };
    "gpt-5.6-sol" = {
      name = "GPT-5.6 Sol";
      contextWindow = 200000;
      maxTokens = 64000;
    };
    "gpt-5.6-terra" = {
      name = "GPT-5.6 Terra";
      contextWindow = 200000;
      maxTokens = 64000;
    };
    "deepseek-v4-flash" = {
      name = "DeepSeek V4 Flash";
      contextWindow = 128000;
      maxTokens = 32000;
    };
    "qwen3.8-max" = {
      name = "Qwen3.8 Max";
      contextWindow = 128000;
      maxTokens = 32000;
    };
  };
in {
  inherit claudeModels extraModels;

  urlFile = "/var/lib/opnix/secrets/opencodeUrl";
  apiKeyFile = "/var/lib/opnix/secrets/opencodeApiKey";

  # The model every agent starts on.
  defaultModel = "claude-opus-5";

  # id -> display name across the whole pool, for consumers that need the menu
  # and nothing else.
  allModelNames = claudeModels // lib.mapAttrs (_: m: m.name) extraModels;
}
