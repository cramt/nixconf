# `nix run .#infra -- <tofu args>`: the Cloudflare infra in infra/, rendered by
# terranix and run through opentofu. The state is a plain file on luna, so tofu
# only ever runs there: from any machine, this copies the runner's closure to
# luna and executes it over ssh. `just deploy` runs `apply` with it before
# touching any host.
{ inputs, lib, config, ... }: {
  perSystem = { pkgs, system, ... }: lib.optionalAttrs (system == "x86_64-linux") (
    let
      tfConfig = inputs.terranix.lib.terranixConfiguration {
        inherit pkgs;
        modules = [ ../../infra ];
      };

      stateHost = config.nixosHosts.luna.address;

      # perSystem pkgs doesn't allow unfree, and op is the only unfree bit here
      op = (import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = p: lib.getName p == "1password-cli";
      })._1password-cli;

      # The provider is the one lib.tf.provider generated the options from, so
      # the types and the binary can't drift apart.
      tofu = pkgs.opentofu.withPlugins (p: [ p.cloudflare_cloudflare ]);

      runner = pkgs.writeShellApplication {
        name = "infra-on-luna";
        runtimeInputs = [ tofu op pkgs.jq ];
        text = ''
          # A missing state file means /vault isn't mounted (or we're not on
          # luna), and tofu would happily plan every resource as new.
          state=$(jq -er '.terraform.backend.local.path' ${tfConfig})
          if [ ! -f "$state" ]; then
            echo "infra: no state at $state, refusing to run against empty state" >&2
            exit 1
          fi

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

          export CLOUDFLARE_EMAIL CLOUDFLARE_API_KEY \
            TF_VAR_domain TF_VAR_ip TF_VAR_atproto TF_VAR_atproto_hannah TF_VAR_email_forwarding
          CLOUDFLARE_EMAIL=$(field "$infrastructure" email)
          CLOUDFLARE_API_KEY=$(field "$cloudflare" apiKey)
          TF_VAR_domain=$(field "$infrastructure" domain)
          TF_VAR_ip=$(field "$infrastructure" ip)
          TF_VAR_atproto=$(field "$atproto" value)
          TF_VAR_atproto_hannah=$(field "$atproto" hannahValue)
          TF_VAR_email_forwarding=$(fields EmailForwarding)

          # Only provider plugins and the backend handle live here; the config
          # is the store path and the state is on /vault.
          work="''${XDG_STATE_HOME:-$HOME/.local/state}/nixconf-infra"
          mkdir -p "$work"
          ln -sfn ${tfConfig} "$work/config.tf.json"
          tofu -chdir="$work" init -input=false -upgrade >/dev/null
          tofu -chdir="$work" "$@"
        '';
      };
    in
    {
      packages.infra = pkgs.writeShellApplication {
        name = "infra";
        runtimeInputs = [ pkgs.nix pkgs.openssh ];
        text = ''
          # Locally built paths are unsigned; root over ssh already owns the box,
          # which is the same reasoning deploy-rs copies with.
          nix copy --no-check-sigs --to ssh-ng://root@${stateHost} ${runner}
          # A tty only when we have one: apply needs it for its prompt, and
          # `state pull > file` would get CRLFs from one.
          tty=()
          if [ -t 0 ] && [ -t 1 ]; then tty=(-t); fi
          # ssh joins its arguments into one remote command line, so quote them.
          args=""
          if [ $# -gt 0 ]; then args=$(printf '%q ' "$@"); fi
          exec ssh "''${tty[@]}" root@${stateHost} ${lib.getExe runner} "$args"
        '';
      };
    });
}
