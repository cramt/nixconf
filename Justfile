add_foundry_zips:
    #!/usr/bin/env nu
    ls ../nix-static/ | each { |it| nix-store --add-fixed sha256 $it.name } | each { |path| cachix push cramt $path }
    null

# Build the current config and activate it on every fleet host that answers on
# the network right now. Powered-off hosts are reported and skipped, not fatal,
# so this is safe to run whenever. `just deploy luna ganymede` narrows it.
#
# The local machine is just another node — it gets deployed over SSH like the
# rest, so this works from whichever host you happen to be sitting at.
deploy *hosts:
    #!/usr/bin/env bash
    set -euo pipefail

    # Node list comes straight out of the flake, so it tracks hosts/ with no
    # second table to keep in sync.
    nodes=$(nix eval --raw .#deploy.nodes --apply \
      'ns: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (n: v: n + " " + v.hostname) ns))')

    want="{{hosts}}"
    for w in $want; do
      grep -qE "^$w " <<<"$nodes" || { echo "unknown host: $w" >&2; exit 1; }
    done
    wanted() { [ -z "$want" ] && return 0; for w in $want; do [ "$w" = "$1" ] && return 0; done; return 1; }

    # Probe over SSH rather than ping: a host can answer ICMP while sshd is down
    # or absent, and that's the case deploy-rs would choke on. All in parallel —
    # an offline host otherwise costs the full connect timeout, serially.
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    while read -r name addr; do
      wanted "$name" || continue
      ( ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new \
          "root@$addr" true >/dev/null 2>&1 && : > "$tmp/$name" ) &
    done <<<"$nodes"
    wait

    targets=()
    while read -r name addr; do
      wanted "$name" || continue
      if [ -e "$tmp/$name" ]; then
        echo "  $name ($addr): online"
        targets+=( ".#$name" )
      else
        echo "  $name ($addr): offline, skipping"
      fi
    done <<<"$nodes"

    if [ ${#targets[@]} -eq 0 ]; then
      echo "no hosts reachable — nothing to deploy" >&2
      exit 1
    fi

    # --inputs-from . pins the CLI to our locked nixpkgs, the same one the
    # activation wrappers are built from, rather than the ambient registry.
    exec nix run --inputs-from . nixpkgs#deploy-rs -- --targets "${targets[@]}" -- --fallback

# Runs as cramt so it reads the server's ~/.t3 state, and by absolute path
# because a non-interactive ssh shell has no user profile on PATH.
#
# Print a T3 Code host's connection string, pairing token and QR (`just t3_pair saturn`)
t3_pair host="luna":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{host}}" = "$(hostname)" ]; then
      /run/current-system/sw/bin/t3 pair --base-dir "$HOME/.t3"
    else
      ssh "cramt@{{host}}" /run/current-system/sw/bin/t3 pair --base-dir /home/cramt/.t3
    fi

clean_ruby:
    rm -rf ~/.local/share/gem/

update_flake:
    nix flake update

update_gems:
    (cd gems && bundle lock --update)

# Bump the from-source / prebuilt packages that live outside flake.lock and npins
# (hardcoded version + hash in packages/*/default.nix). nix-update follows each
# package's upstream latest release and rewrites version + hashes in place.
# steamlink is intentionally absent (no upstream version feed — see its default.nix).
update_packages:
    nix run nixpkgs#nix-update -- --flake agentsview
    nix run nixpkgs#nix-update -- --flake agent-browser
    nix run nixpkgs#nix-update -- --flake cockatrice

# Bump every pinned source (flake.lock, gems, npins, packages). Run daily by
# .github/workflows/update.yml, which pushes the result to the `update` branch
# as a PR and prebuilds it into cachix — merge that PR to update.
update:
    just update_flake
    just update_gems
    npins update
    just update_packages

tf *args:
    #!/usr/bin/env bash
    export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/opnix-token)
    export PG_CONN_STR="postgres://terraformremotestate:$(op read 'op://Homelab/TerraformRemoteState/password')@$(op read 'op://Homelab/Infrastructure/lunaInternalAddress'):5432"
    tofu -chdir=infra {{args}}
