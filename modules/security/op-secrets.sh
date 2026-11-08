# Renders every secret in the manifest (JSON lines from secrets.nix) with
# `op read`, a few at a time: each read is its own ~1.5 s service-account
# sign-in, almost all of it network round trips.
#
# A secret is only replaced once its new value is fully written, so a failed
# read keeps the last good one on disk, and the run still exits nonzero so
# systemd retries. Services listed against a secret whose value changed get a
# try-restart; on a first render they haven't started yet (they're ordered
# after this unit), so there's nothing to restart.
manifest=$1
token_file=$2
dir=$3

if [ ! -s "$token_file" ]; then
  # Not a failure: a host without a token keeps whatever is already rendered
  # rather than failing boot.
  echo "op-secrets: no token at $token_file, keeping what's on disk" >&2
  exit 0
fi
OP_SERVICE_ACCOUNT_TOKEN=$(<"$token_file")
export OP_SERVICE_ACCOUNT_TOKEN

install -d -m 0751 "$dir"
status=$(mktemp -d)
trap 'rm -rf "$status"' EXIT

render() {
  local name=$1 reference=$2 path=$3 owner=$4 group=$5 mode=$6
  local new="$path.new"
  rm -f "$new"
  # --out-file writes the bare value: no trailing newline on a field, and a
  # file attachment byte for byte. Consumers rely on both.
  if ! timeout 120 op read --out-file "$new" "$reference" >/dev/null; then
    rm -f "$new"
    echo "op-secrets: $name: reading $reference failed, keeping the old value" >&2
    echo failed >"$status/$name"
    return
  fi
  chown "$owner:$group" "$new"
  chmod "$mode" "$new"
  if [ ! -e "$path" ]; then
    mv -f "$new" "$path"
    echo new >"$status/$name"
  elif cmp -s "$new" "$path"; then
    # Still apply owner/mode, in case only those changed.
    mv -f "$new" "$path"
    echo same >"$status/$name"
  else
    mv -f "$new" "$path"
    echo changed >"$status/$name"
  fi
}

while IFS=$'\t' read -r name reference path owner group mode; do
  while [ "$(jobs -rp | wc -l)" -ge 6 ]; do wait -n || true; done
  render "$name" "$reference" "$path" "$owner" "$group" "$mode" &
done < <(jq -r '[.name, .reference, .path, .owner, .group, .mode] | @tsv' "$manifest")
wait

failed=() restart=()
while read -r name services; do
  case $(cat "$status/$name" 2>/dev/null || echo failed) in
    failed) failed+=("$name") ;;
    changed) read -ra s <<<"$services"; restart+=("${s[@]}") ;;
  esac
done < <(jq -r '"\(.name) \(.services | join(" "))"' "$manifest")

if [ ${#restart[@]} -gt 0 ]; then
  mapfile -t restart < <(printf '%s\n' "${restart[@]}" | sort -u)
  echo "op-secrets: values changed, restarting ${restart[*]}"
  # --no-block: those units are ordered after this one, so waiting on them
  # from inside it would deadlock.
  systemctl try-restart --no-block "${restart[@]/%/.service}"
fi

if [ ${#failed[@]} -gt 0 ]; then
  echo "op-secrets: failed: ${failed[*]}" >&2
  exit 1
fi
echo "op-secrets: rendered $(jq -s length "$manifest") secrets"
