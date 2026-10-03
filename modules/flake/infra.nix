# `nix run .#infra -- <tofu args>`: the Cloudflare infra in infra/, rendered by
# terranix and run through opentofu against the pg state on luna. `just deploy`
# runs `apply` with it before touching any host.
{ inputs, lib, ... }: {
  perSystem = { pkgs, system, ... }: lib.optionalAttrs (system == "x86_64-linux") (
    let
      config = inputs.terranix.lib.terranixConfiguration {
        inherit pkgs;
        modules = [ ../../infra ];
      };

      # perSystem pkgs doesn't allow unfree, and op is the only unfree bit here
      op = (import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = p: lib.getName p == "1password-cli";
      })._1password-cli;

      # The provider is the one lib.tf.provider generated the options from, so
      # the types and the binary can't drift apart.
      tofu = pkgs.opentofu.withPlugins (p: [ p.cloudflare_cloudflare ]);
    in
    {
      packages.infra = pkgs.writeShellApplication {
        name = "infra";
        runtimeInputs = [ tofu op pkgs.jq ];
        text = ''
          export OP_SERVICE_ACCOUNT_TOKEN
          OP_SERVICE_ACCOUNT_TOKEN=$(< /etc/opnix-token)

          # Every item keeps its values as top-level fields; the notes field
          # (purpose NOTES) is the only one that isn't data.
          fields() {
            op item get "$1" --vault Homelab --format json \
              | jq -c '[.fields[] | select(.purpose == null) | { (.label): .value }] | add'
          }
          infrastructure=$(fields Infrastructure)
          cloudflare=$(fields Cloudflare)
          atproto=$(fields AtprotoDomain)
          field() { jq -er --arg k "$2" '.[$k]' <<<"$1"; }

          export CLOUDFLARE_EMAIL CLOUDFLARE_API_KEY PG_CONN_STR \
            TF_VAR_domain TF_VAR_ip TF_VAR_atproto TF_VAR_atproto_hannah TF_VAR_email_forwarding
          CLOUDFLARE_EMAIL=$(field "$infrastructure" email)
          CLOUDFLARE_API_KEY=$(field "$cloudflare" apiKey)
          PG_CONN_STR="postgres://terraformremotestate:$(op read op://Homelab/TerraformRemoteState/password)@$(field "$infrastructure" lunaInternalAddress):5432"
          TF_VAR_domain=$(field "$infrastructure" domain)
          TF_VAR_ip=$(field "$infrastructure" ip)
          TF_VAR_atproto=$(field "$atproto" value)
          TF_VAR_atproto_hannah=$(field "$atproto" hannahValue)
          TF_VAR_email_forwarding=$(fields EmailForwarding)

          # Only provider plugins and the backend handle live here; the config
          # is the store path and the state is in postgres.
          work="''${XDG_STATE_HOME:-$HOME/.local/state}/nixconf-infra"
          mkdir -p "$work"
          ln -sfn ${config} "$work/config.tf.json"
          tofu -chdir="$work" init -input=false -upgrade >/dev/null
          tofu -chdir="$work" "$@"
        '';
      };
    });
}
