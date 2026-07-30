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
TCP_HOST="${NETWATCH_TCP_HOST:-cloudflare.com}"
INTERVAL="${NETWATCH_INTERVAL:-20}"

HEADER="ts,gw_loss%,gw_avg_ms,icmp_loss%,icmp_avg_ms,icmp_max_ms,tcp_fail,tcp_avg_ms,tcp_max_ms,retrans_ratio%,wan_down_bps,wan_up_bps"

mkdir -p "$(dirname "$LOG")"
# The v1 schema measured WAN health with ICMP alone. That turned out to be worthless on
# this connection: the ISP deprioritises ICMP hard under load, so "70% loss" samples sat
# alongside 100 MB transfers completing at 0.010% retransmit. TCP connect timing is the
# honest signal. Old data is kept, but under its own name so the schemas never interleave.
if [ -s "$LOG" ] && [ "$(head -1 "$LOG")" != "$HEADER" ]; then
  mv "$LOG" "${LOG%.csv}-icmp-only-$(date +%Y%m%d%H%M%S).csv"
fi
[ -s "$LOG" ] || echo "$HEADER" >> "$LOG"

# ping exits non-zero on total loss, which is a sample we specifically want to keep,
# so every invocation is guarded against set -e.
probe() {
  local host=$1 out loss avg max
  out=$(ping -c 20 -i 0.5 -W 10 -q "$host" 2>/dev/null || true)
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

# Real traffic-path latency. ICMP can be policed into meaninglessness; a TCP handshake
# to :443 rides the same queues as actual traffic, so a multi-second connect here is a
# stall users genuinely feel — unlike a multi-second ping, which may be pure deprioritisation.
tcpprobe() {
  local n=8 fail=0 sum=0 max=0 t ms
  for _ in $(seq 1 "$n"); do
    t=$(curl -s -o /dev/null -w '%{time_connect}' --max-time 10 \
        "https://${TCP_HOST}/" 2>/dev/null || echo "")
    if [ -z "$t" ] || [ "$t" = "0.000000" ]; then
      fail=$((fail+1))
    else
      ms=$(awk -v x="$t" 'BEGIN{printf "%.1f", x*1000}')
      sum=$(awk -v a="$sum" -v b="$ms" 'BEGIN{printf "%.1f", a+b}')
      max=$(awk -v a="$max" -v b="$ms" 'BEGIN{print (b>a? b : a)}')
    fi
  done
  # Trailing newline matters: `read` returns non-zero on EOF-without-newline, which
  # set -e then treats as fatal and the sampler dies silently after writing its header.
  awk -v f="$fail" -v s="$sum" -v n="$(( n - fail ))" -v m="$max" \
    'BEGIN{printf "%d %.1f %.1f\n", f, (n>0? s/n : 0), m}'
}

counter() { nstat -az 2>/dev/null | awk -v k="$1" '$1==k{print $2}'; }

rt_prev=$(counter TcpRetransSegs); rt_prev=${rt_prev:-0}
out_prev=$(counter TcpOutSegs);    out_prev=${out_prev:-0}

while :; do
  read -r gwl gwa _  < <(probe "$GW")
  read -r wl  wa  wm < <(probe "$WAN")
  read -r tf  ta  tm < <(tcpprobe)
  read -r dbps ubps  < <(wanrates)

  rt_now=$(counter TcpRetransSegs); rt_now=${rt_now:-$rt_prev}
  out_now=$(counter TcpOutSegs);    out_now=${out_now:-$out_prev}
  ratio=$(awk -v r="$(( rt_now - rt_prev ))" -v o="$(( out_now - out_prev ))" \
          'BEGIN{printf "%.3f", (o>0? r*100.0/o : 0)}')
  rt_prev=$rt_now; out_prev=$out_now

  echo "$(date -Is),${gwl},${gwa},${wl},${wa},${wm},${tf},${ta},${tm},${ratio},${dbps},${ubps}" >> "$LOG"
  sleep "$INTERVAL"
done
