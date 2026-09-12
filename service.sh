#!/system/bin/sh
# service.sh - runs late at boot (after service stage).
# Purely dynamic: if you never created a set/rule, this does nothing at all.
# If you did (via ipctl.sh or the WebUI), this replays exactly that state.

MODDIR="$(cd "$(dirname "$0")" && pwd)"
DATA="/data/adb/ipset_arm64_data"
mkdir -p "$DATA"

# start each boot with a clean log - this file is meant to answer
# "what did the last boot do", not accumulate history across boots
: > "$DATA/service.log"

# small delay so netfilter/iptables backend on some ROMs is fully ready
sleep 5

sh "$MODDIR/ipctl.sh" restore >> "$DATA/service.log" 2>&1
