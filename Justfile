add_foundry_zips:
    #!/usr/bin/env nu
    ls ../nix-static/ | each { |it| nix-store --add-fixed sha256 $it.name } | each { |path| cachix push cramt $path }
    null

# Nix defaults to "one build per core, and every core inside each build", which
# pins the machine for the whole deploy — fine on saturn, miserable on a laptop
# you're still using. jobs * cores is the ceiling; the daemon honours both
# because cramt is a trusted-user. Bump either for a one-off:
# `just jobs=8 cores=8 deploy luna`. Empty jobs means nproc/4 of whichever
# machine ends up building, which with `on=` isn't this one.
jobs := ""
cores := "2"

# Run the deploy from another host: `just on=luna deploy` ships the flake to
# luna and runs the deploy there, so luna builds and pushes closures out. Spares
# the machine you're on the CPU, and the uplink when luna is a target anyway.
on := ""

# Build the current config and activate it on every fleet host that answers on
# the network right now. Powered-off hosts are reported and skipped, not fatal,
# so this is safe to run whenever. `just deploy luna ganymede` narrows it.
#
# The Cloudflare infra (infra/, via `nix run .#infra`) goes first, so DNS for a
# new vhost exists before the host asks ACME for its cert. It's a target named
# `infra`: a bare `just deploy` includes it, `just deploy luna` skips it,
# `just deploy infra` runs it alone. tofu asks before applying any change.
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

    want=""; infra=false
    if [ -z "{{hosts}}" ]; then infra=true; fi
    for w in {{hosts}}; do
      if [ "$w" = infra ]; then infra=true; else want+="$w "; fi
    done
    for w in $want; do
      grep -qE "^$w " <<<"$nodes" || { echo "unknown host: $w" >&2; exit 1; }
    done

    if $infra; then
      nix run .#infra -- apply
      # only `infra` named: an empty $want would otherwise mean every host
      if [ -n "{{hosts}}" ] && [ -z "$want" ]; then exit 0; fi
    fi

    # infra already ran here (it executes on luna regardless), so the remote run
    # gets an explicit host list: an empty one would mean "everything + infra".
    if [ -n "{{on}}" ] && [ "{{on}}" != "$(hostname)" ]; then
      addr=$(awk -v h="{{on}}" '$1 == h { print $2 }' <<<"$nodes")
      [ -n "$addr" ] || { echo "unknown host for on=: {{on}}" >&2; exit 1; }
      [ -n "$want" ] || want=$(cut -d' ' -f1 <<<"$nodes" | tr '\n' ' ')
      # Source tree (uncommitted edits included) plus every locked input, so
      # the remote eval is this one exactly, no git checkout needed over there.
      # Not `flake archive --to`: Lix's has no --no-check-sigs, and fetched
      # inputs are unsigned. Root over ssh owns the box anyway (see infra.nix).
      tree=$(nix flake archive --json --dry-run .)
      src=$(jq -r .path <<<"$tree")
      nix copy --no-check-sigs --to "ssh-ng://root@$addr" $(jq -r '.. | .path? // empty' <<<"$tree")
      # -A: the remote deploy reaches the fleet as root with our keys, same as
      # from here. on= cleared so it can't bounce again. git because Lix shells
      # out to it for eval-time fetchGit (niri's cargo git deps), and root's
      # PATH on a server has none.
      tty=(); if [ -t 0 ] && [ -t 1 ]; then tty=(-t); fi
      exec ssh -A "${tty[@]}" "root@$addr" "cd $src && nix shell --inputs-from . nixpkgs#just nixpkgs#git --command \
        just on= jobs={{jobs}} cores={{cores}} deploy $want"
    fi
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

    jobs="{{jobs}}"
    [ -n "$jobs" ] || jobs=$(nproc | awk '{n = int($1 / 4); print (n < 1 ? 1 : n)}')

    # --inputs-from . pins the CLI to our locked nixpkgs, the same one the
    # activation wrappers are built from, rather than the ambient registry.
    exec nix run --inputs-from . nixpkgs#deploy-rs -- --targets "${targets[@]}" -- \
      --fallback --max-jobs "$jobs" --cores {{cores}}

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
    nix run nixpkgs#nix-update -- --flake cpa-prometheus
    # Cockatrice cuts Development betas far more often than Release builds, and
    # the releases/tags atom feeds nix-update reads only carry the 10 newest
    # entries — since 2026-06-26-Release-3.0.2 there has been no Release tag in
    # that window at all. Without the regex nix-update errors out on the beta it
    # finds; with it there is simply nothing to match, which it also calls an
    # error. Neither is a reason to fail the whole update run.
    # Drop the `||` once upstream cuts a 3.1.0 Release and the feed holds one again.
    nix run nixpkgs#nix-update -- --flake cockatrice \
      --version-regex '^(\d{4}-\d{2}-\d{2}-Release-[0-9.]+)$' \
      || echo ">> cockatrice: no Release tag in the atom feed window, leaving it pinned"
    nix run nixpkgs#nix-update -- --flake rhystic-tracker
    # rhystic-tracker's avatar extractor stack, pinned per-package off PyPI.
    nix run nixpkgs#nix-update -- --flake unitypy
    nix run nixpkgs#nix-update -- --flake texture2ddecoder
    nix run nixpkgs#nix-update -- --flake etcpak
    nix run nixpkgs#nix-update -- --flake astc-encoder-py
    nix run nixpkgs#nix-update -- --flake tpk-ar
    nix run nixpkgs#nix-update -- --flake fmod-toolkit
    nix run nixpkgs#nix-update -- --flake pyfmodex

# Bump every pinned source (flake.lock, gems, npins, packages). Run daily by
# .github/workflows/update.yml, which pushes the result to the `update` branch
# as a PR and prebuilds it into cachix — merge that PR to update.
#
# Anonymous GitHub API calls cap out at 60/h, which flake update + npins +
# nix-update blow through fast. Borrow gh's token (or CI's GITHUB_TOKEN) and
# hand it to all three: nix via access-tokens, npins/nix-update via GITHUB_TOKEN.
update:
    #!/usr/bin/env bash
    set -euo pipefail
    GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
    if [ -n "$GITHUB_TOKEN" ]; then
      export GITHUB_TOKEN
      export NIX_CONFIG="access-tokens = github.com=$GITHUB_TOKEN${NIX_CONFIG:+$'\n'$NIX_CONFIG}"
    else
      echo ">> no GitHub token (gh not authed?), running anonymous, expect rate limits" >&2
    fi
    just update_flake
    just update_gems
    # npins shells out to skopeo for docker pins; CI's runner image happens to
    # ship it, a desktop doesn't.
    nix shell --inputs-from . nixpkgs#npins nixpkgs#skopeo --command npins update
    just update_packages

# Run OpenTofu against the Cloudflare infra (`just tf plan`); `just deploy` applies it
tf *args:
    nix run .#infra -- {{args}}
