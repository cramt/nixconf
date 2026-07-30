#!/usr/bin/env bash
# Records a per-minute network health sample so an *intermittent* fault leaves evidence.
# Spot tests are useless for this: by the time a human notices and runs one, the episode
# is already over — which is exactly how the 2026-07-30 investigation went.
#
# The gateway-vs-WAN split is the whole point:
#   loss on both              -> fault is inside the house (NIC, cable, switch, router)
#   clean gateway, lossy WAN  -> fault is upstream (DOCSIS segment / ISP), nothing local to fix
#
# Disable via myHomeManager.netwatch.enable once the underlying fault is resolved.

set -u
LOG="${NETWATCH_LOG:-$HOME/.local/share/netwatch/netwatch.csv}"
GW="$(ip route | awk '/^default/{print $3; exit}')"
WAN="${NETWATCH_TARGET:-1.1.1.1}"
INTERVAL="${NETWATCH_INTERVAL:-20}"

mkdir -p "$(dirname "$LOG")"
[ -s "$LOG" ] || echo "ts,gw_loss%,gw_avg_ms,wan_loss%,wan_avg_ms,wan_max_ms,retrans_ratio%,wan_down_bps,wan_up_bps" >> "$LOG"

# ping exits non-zero on total loss, which is a sample we specifically want to keep,
# so every invocation is guarded against set -e.
probe() {
  local host=$1 out loss avg max
  out=$(ping -c 20 -i 0.5 -W 2 -q "$host" 2>/dev/null || true)
  loss=$(printf '%s' "$out" | grep -oE '[0-9.]+% packet loss' | grep -oE '^[0-9.]+' || true)
  avg=$(printf '%s' "$out" | awk -F'/' '/rtt|round-trip/{print $5}')
  max=$(printf '%s' "$out" | awk -F'/' '/rtt|round-trip/{print $6}')
  echo "${loss:-100} ${avg:-} ${max:-}"
}

# Fritz!Box WAN throughput via the unauthenticated TR-064 LAN endpoint, so a sample can be
# read in context: loss while the link is busy means something very different from loss
# while it is idle.
wanrates() {
  local xml d u
  xml=$(curl -s --max-time 5 "http://${GW}:49000/igdupnp/control/WANCommonIFC1" \
    -H 'Content-Type: text/xml; charset="utf-8"' \
    -H 'SoapAction: urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1#GetAddonInfos' \
    -d '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetAddonInfos xmlns:u="urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1"/></s:Body></s:Envelope>' 2>/dev/null || true)
  d=$(printf '%s' "$xml" | grep -oP '(?<=<NewByteReceiveRate>)[0-9]+' | head -1 || true)
  u=$(printf '%s' "$xml" | grep -oP '(?<=<NewByteSendRate>)[0-9]+' | head -1 || true)
  echo "$(( ${d:-0} * 8 )) $(( ${u:-0} * 8 ))"
}

counter() { nstat -az 2>/dev/null | awk -v k="$1" '$1==k{print $2}'; }

rt_prev=$(counter TcpRetransSegs); rt_prev=${rt_prev:-0}
out_prev=$(counter TcpOutSegs);    out_prev=${out_prev:-0}

while :; do
  read -r gwl gwa _  < <(probe "$GW")
  read -r wl  wa  wm < <(probe "$WAN")
  read -r dbps ubps  < <(wanrates)

  rt_now=$(counter TcpRetransSegs); rt_now=${rt_now:-$rt_prev}
  out_now=$(counter TcpOutSegs);    out_now=${out_now:-$out_prev}
  ratio=$(awk -v r="$(( rt_now - rt_prev ))" -v o="$(( out_now - out_prev ))" \
          'BEGIN{printf "%.3f", (o>0? r*100.0/o : 0)}')
  rt_prev=$rt_now; out_prev=$out_now

  echo "$(date -Is),${gwl},${gwa},${wl},${wa},${wm},${ratio},${dbps},${ubps}" >> "$LOG"
  sleep "$INTERVAL"
done
