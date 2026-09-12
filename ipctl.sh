#!/system/bin/sh
# ipctl.sh - dynamic control layer for ipset-arm64 module
# Nothing here is static: no set, no rule exists unless you create it.
#
# Usage (as root):
#   sh /data/adb/modules/ipset-arm64/ipctl.sh <command> [args]
#
# Commands:
#   status                                   - kernel/binary capability check
#   list [setname]                           - list all sets (summary) or one set's members
#   types                                    - list every supported set type
#   owned                                    - list the sets this module created
#   create <name> [type] [inet|inet6]        - create a set (default type: hash:ip)
#   destroy <name>                           - destroy a set (only ones we created)
#   add <name> <entry> [entry ...]           - add one or more members
#   del <name> <entry> [entry ...]           - remove one or more members
#   test <name> <entry>                      - check if an entry is a member
#   rule-add <name> [chain] [dir] [target] [uid]  - add firewall rule using the set (defaults: OUTPUT dst DROP; uid = per-app filter, OUTPUT chain only)
#   rule-del <name> [chain] [dir] [target] [uid]  - remove that firewall rule
#   apps                                     - list installed packages with their Android UID (for per-app filtering)
#   rules                                    - list currently active dynamic rules
#   bootlog                                  - show last boot's restore log (what service.sh did)
#   save                                     - persist current set state to disk
#   restore                                  - reload persisted sets + rules (used by service.sh at boot)
#   bootlog-clear                            - clear that log
#   flush-all                                - destroy every set THIS MODULE created and remove
#                                              every rule it manages. Sets belonging to other
#                                              apps are left untouched.

set -u

MODDIR="$(cd "$(dirname "$0")" && pwd)"

# Persisted data lives OUTSIDE the module directory on purpose: on update,
# Magisk/KernelSU replace $MODDIR entirely with the new zip's contents, so
# anything stored inside it (e.g. $MODDIR/data) is wiped on every flash.
# This external path survives updates and is only removed by uninstall.sh.
DATA="/data/adb/ipset_arm64_data"
mkdir -p "$DATA"

# one-time migration from the old (broken) in-module location, if present
if [ -d "$MODDIR/data" ] && [ -z "$(ls -A "$DATA" 2>/dev/null)" ]; then
    cp -a "$MODDIR/data/." "$DATA/" 2>/dev/null
fi
STATE="$DATA/sets.save"
RULES="$DATA/rules.conf"
LOG="$DATA/ipctl.log"

# Names of the sets THIS MODULE created. Everything that saves,
# restores or destroys sets is scoped to this list.
#
# Why: `ipset` has one flat, system-wide namespace. Earlier versions
# used bare `ipset save` (which dumps every set on the device) and
# `for n in $(ipset list -n); do ipset destroy "$n"; done` (which
# destroys every set on the device). That meant this module quietly
# adopted sets belonging to AFWall+, a VPN app or a user script into
# its own state file, restored them at boot as if they were ours, and
# destroyed them on `flush-all` - which uninstall.sh calls. Deleting
# another program's firewall state on uninstall is not acceptable, so
# ownership is now explicit.
OWNED="$DATA/owned.list"
touch "$OWNED"

touch "$RULES"

# One-time migration for installs that predate the manifest: adopt the
# set names already present in our own save file. Those are the ones
# this module was managing (correctly or not) before the fix, so losing
# them on upgrade would be worse than inheriting them. Sets created by
# anything else from here on are never touched.
if [ ! -s "$OWNED" ] && [ -s "$STATE" ]; then
    awk '$1=="create" {print $2}' "$STATE" 2>/dev/null | sort -u > "$OWNED"
fi

own_add() {
    grep -qx "$1" "$OWNED" 2>/dev/null || echo "$1" >> "$OWNED"
}

own_remove() {
    grep -vx "$1" "$OWNED" > "${OWNED}.tmp" 2>/dev/null
    mv "${OWNED}.tmp" "$OWNED"
}

own_list() {
    [ -s "$OWNED" ] && cat "$OWNED" || true
}

own_has() {
    grep -qx "$1" "$OWNED" 2>/dev/null
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# Prefer the binary shipped in the module, fall back to PATH
if [ -x "$MODDIR/system/bin/ipset" ]; then
    IPSET="$MODDIR/system/bin/ipset"
elif command -v ipset >/dev/null 2>&1; then
    IPSET="$(command -v ipset)"
else
    echo "ERROR: ipset binary not found (checked module dir and PATH)"
    exit 1
fi

IPTABLES="$(command -v iptables 2>/dev/null || echo /system/bin/iptables)"

die() {
    echo "ERROR: $*"
    log "ERROR: $*"
    exit 1
}

# ---- input validation (defense in depth, since input may come from a UI) ----

valid_setname() {
    # ipset set names: max 31 chars, keep it conservative
    echo "$1" | grep -Eq '^[a-zA-Z0-9_]{1,31}$'
}

valid_settype() {
    # Every set type the kernel provides. The module used to accept
    # only hash:ip and hash:net, which meant the MAC-keyed types - the
    # ones you cannot express any other way - were unreachable even
    # though the kernel ships them.
    case "$1" in
        bitmap:ip|bitmap:ip,mac|bitmap:port) return 0 ;;
        hash:ip|hash:mac|hash:ip,mac|hash:net|hash:net,net) return 0 ;;
        hash:ip,port|hash:ip,port,ip|hash:ip,port,net) return 0 ;;
        hash:ip,mark|hash:net,port|hash:net,port,net|hash:net,iface) return 0 ;;
        list:set) return 0 ;;
        *) return 1 ;;
    esac
}

valid_family() {
    case "$1" in
        inet|inet6) return 0 ;;
        *) return 1 ;;
    esac
}

valid_entry() {
    # Deliberately NOT a syntax check. ipset itself is the authority on
    # what a valid member looks like for each of the 15 set types, and
    # duplicating that here would only go stale - the old IPv4-only
    # regex already rejected perfectly good IPv6 addresses and MAC
    # addresses outright.
    #
    # What this DOES guarantee is that nothing reaching the shell can
    # break out of the argument: no whitespace, no quotes, no $ ` ; | &
    # < > ( ) * ? or backslashes. Only the characters that legitimately
    # appear in ipset members are allowed through - hex digits, dots,
    # colons, slashes, commas, hyphens, underscores - and the result is
    # handed to ipset, which rejects anything malformed with a clear
    # error of its own.
    case "$1" in
        "") return 1 ;;
        *[!0-9a-fA-F.:/,_-]*) return 1 ;;
    esac
    [ "${#1}" -le 128 ]
}

valid_chain() {
    case "$1" in
        INPUT|OUTPUT|FORWARD) return 0 ;;
        *) return 1 ;;
    esac
}

valid_dir() {
    case "$1" in
        src|dst) return 0 ;;
        *) return 1 ;;
    esac
}

valid_target() {
    case "$1" in
        DROP|ACCEPT|REJECT|RETURN) return 0 ;;
        *) return 1 ;;
    esac
}

# ---- commands ----

cmd_status() {
    echo "== ipset-arm64 status =="
    echo "ipset binary   : $IPSET"
    "$IPSET" --version >/dev/null 2>&1 && echo "  runs           : OK" || echo "  runs           : FAIL"

    echo "iptables binary: $IPTABLES"
    [ -x "$IPTABLES" ] && echo "  present        : OK" || echo "  present        : MISSING"

    if [ -r /proc/config.gz ]; then
        # Read the compressed config once, not once per symbol.
        _kcfg=$(zcat /proc/config.gz 2>/dev/null)
        for cfg in CONFIG_IP_SET CONFIG_IP_SET_HASH_IP CONFIG_IP_SET_HASH_NET CONFIG_IP_SET_HASH_MAC CONFIG_NETFILTER_XT_SET; do
            val=$(echo "$_kcfg" | grep "^${cfg}=" | cut -d= -f2)
            if [ -n "$val" ]; then
                echo "  $cfg = $val"
            else
                echo "  $cfg = not set / not found"
            fi
        done
    else
        echo "  /proc/config.gz not readable on this device - skipping kernel config check"
        echo "  (falling back to functional test below)"
    fi

    if "$IPTABLES" -m set --help >/dev/null 2>&1; then
        echo "  xt_set match   : OK"
    else
        echo "  xt_set match   : possibly missing (iptables -m set --help failed)"
    fi

    echo ""
    echo "Sets created by this module:"
    if [ -s "$OWNED" ]; then
        own_list | while read -r n; do
            [ -z "$n" ] && continue
            if "$IPSET" list -n 2>/dev/null | grep -qx "$n"; then
                echo "  - $n"
            else
                echo "  - $n  (in manifest but not currently loaded)"
            fi
        done
    else
        echo "  (none)"
    fi

    echo ""
    echo "Other sets on this device (NOT managed here, never touched):"
    _others=$("$IPSET" list -n 2>/dev/null | grep -vxF -f "$OWNED" 2>/dev/null)
    if [ -n "$_others" ]; then
        echo "$_others" | sed 's/^/  - /'
    else
        echo "  (none)"
    fi

    echo ""
    echo "Active dynamic rules (from $RULES):"
    if [ -s "$RULES" ]; then
        sed 's/^/  /' "$RULES"
    else
        echo "  (none)"
    fi
}

cmd_list() {
    if [ -n "${1:-}" ]; then
        valid_setname "$1" || die "invalid set name"
        "$IPSET" list "$1" || die "set '$1' does not exist"
    else
        names=$("$IPSET" list -n 2>/dev/null)
        if [ -z "$names" ]; then
            echo "(no sets defined)"
            return 0
        fi
        for n in $names; do
            count=$("$IPSET" list "$n" 2>/dev/null | grep "^Number of entries:" | awk '{print $NF}')
            type=$("$IPSET" list "$n" 2>/dev/null | grep "^Type:" | awk '{print $2}')
            echo "$n  type=$type  entries=$count"
        done
    fi
}

cmd_create() {
    name="${1:-}"; type="${2:-hash:ip}"; family="${3:-}"
    valid_setname "$name" || die "invalid set name (use letters/digits/underscore, max 31 chars)"
    valid_settype "$type" || die "unsupported type '$type' (see: ipctl.sh types)"
    extra=""
    if [ -n "$family" ]; then
        valid_family "$family" || die "invalid family '$family' (use inet or inet6)"
        # bitmap:* and hash:mac have no address family to speak of
        case "$type" in
            bitmap:*|hash:mac) die "type '$type' does not take a family" ;;
        esac
        extra="family $family"
    fi
    "$IPSET" create "$name" "$type" $extra 2>&1 || die "failed to create set"
    own_add "$name"
    log "created set $name ($type${extra:+ $extra})"
    cmd_save
    echo "OK: created '$name' ($type)"
}

cmd_destroy() {
    name="${1:-}"
    valid_setname "$name" || die "invalid set name"
    # refuse to destroy a set that still has an active rule - drop the rule first
    if grep -q "|$name|" "$RULES" 2>/dev/null; then
        die "set '$name' still has active firewall rule(s); run rule-del first (see: rules)"
    fi
    own_has "$name" || die "'$name' was not created by this module - refusing to destroy it. Use ipset directly if you really mean to."
    "$IPSET" destroy "$name" 2>&1 || die "failed to destroy set (does it exist?)"
    own_remove "$name"
    log "destroyed set $name"
    cmd_save
    echo "OK: destroyed '$name'"
}

cmd_add() {
    name="${1:-}"
    valid_setname "$name" || die "invalid set name"
    shift 2>/dev/null
    [ $# -ge 1 ] || die "nothing to add - usage: add <set> <entry> [entry ...]"
    # Several entries per call, and ONE save at the end. cmd_save
    # rewrites the whole state file, so saving inside the loop made
    # bulk loading quadratic - a thousand addresses meant a thousand
    # full dumps.
    _n=0
    for e in "$@"; do
        valid_entry "$e" || die "invalid entry '$e' (unsupported characters, or too long)"
        "$IPSET" add "$name" "$e" 2>&1 || die "failed to add '$e' (set may not exist, or duplicate entry)"
        _n=$((_n + 1))
    done
    log "added $_n entr(y/ies) to $name"
    cmd_save
    echo "OK: added $_n entr(y/ies) to '$name'"
}

cmd_del() {
    name="${1:-}"
    valid_setname "$name" || die "invalid set name"
    shift 2>/dev/null
    [ $# -ge 1 ] || die "nothing to remove - usage: del <set> <entry> [entry ...]"
    _n=0
    for e in "$@"; do
        valid_entry "$e" || die "invalid entry '$e' (unsupported characters, or too long)"
        "$IPSET" del "$name" "$e" 2>&1 || die "failed to remove '$e' (was it a member?)"
        _n=$((_n + 1))
    done
    log "removed $_n entr(y/ies) from $name"
    cmd_save
    echo "OK: removed $_n entr(y/ies) from '$name'"
}

cmd_test() {
    name="${1:-}"; ip="${2:-}"
    valid_setname "$name" || die "invalid set name"
    valid_entry "$ip" || die "invalid entry '$ip' (unsupported characters, or too long)"
    "$IPSET" test "$name" "$ip"
}

cmd_rule_add() {
    name="${1:-}"; chain="${2:-OUTPUT}"; dir="${3:-dst}"; target="${4:-DROP}"; uid="${5:-}"
    valid_setname "$name" || die "invalid set name"
    valid_chain "$chain" || die "invalid chain (INPUT/OUTPUT/FORWARD)"
    valid_dir "$dir" || die "invalid direction (src/dst)"
    valid_target "$target" || die "invalid target (DROP/ACCEPT/REJECT/RETURN)"

    owner_args=""
    if [ -n "$uid" ]; then
        echo "$uid" | grep -Eq '^[0-9]+$' || die "invalid uid '$uid'"
        [ "$chain" = "OUTPUT" ] || die "per-app filtering (uid) only works on the OUTPUT chain - the owner match has no meaning for INPUT/FORWARD"
        owner_args="-m owner --uid-owner $uid"
    fi

    # backward-compatible key: only grows to 5 fields when a uid is actually used,
    # so existing rules.conf entries from before per-app support keep working unchanged
    key="${chain}|${name}|${dir}|${target}"
    [ -n "$uid" ] && key="${key}|${uid}"

    if grep -qx "$key" "$RULES" 2>/dev/null; then
        echo "OK: rule already active ($key)"
        return 0
    fi

    "$IPTABLES" -C "$chain" $owner_args -m set --match-set "$name" "$dir" -j "$target" 2>/dev/null
    already_in_kernel=$?

    if [ "$already_in_kernel" -ne 0 ]; then
        "$IPTABLES" -I "$chain" $owner_args -m set --match-set "$name" "$dir" -j "$target" \
            || die "failed to insert iptables rule"
    fi

    echo "$key" >> "$RULES"
    log "rule added: $key"
    echo "OK: rule active -> $chain, match-set $name $dir, -j $target${uid:+ (app uid $uid)}"
}

cmd_rule_del() {
    name="${1:-}"; chain="${2:-OUTPUT}"; dir="${3:-dst}"; target="${4:-DROP}"; uid="${5:-}"
    valid_setname "$name" || die "invalid set name"
    valid_chain "$chain" || die "invalid chain"
    valid_dir "$dir" || die "invalid direction"
    valid_target "$target" || die "invalid target"

    owner_args=""
    if [ -n "$uid" ]; then
        echo "$uid" | grep -Eq '^[0-9]+$' || die "invalid uid '$uid'"
        owner_args="-m owner --uid-owner $uid"
    fi

    key="${chain}|${name}|${dir}|${target}"
    [ -n "$uid" ] && key="${key}|${uid}"

    if "$IPTABLES" -C "$chain" $owner_args -m set --match-set "$name" "$dir" -j "$target" 2>/dev/null; then
        "$IPTABLES" -D "$chain" $owner_args -m set --match-set "$name" "$dir" -j "$target" 2>&1
    fi
    grep -vx "$key" "$RULES" > "${RULES}.tmp" 2>/dev/null
    mv "${RULES}.tmp" "$RULES"
    log "rule removed: $key"
    echo "OK: rule removed -> $key"
}

cmd_apps() {
    # lists installed packages with their Android UID, for per-app rule filtering
    pm list packages -U 2>/dev/null | awk -F'[: ]+' 'NF>=4 {print $2"|"$4}' | sort
}

cmd_rules() {
    if [ -s "$RULES" ]; then
        cat "$RULES"
    else
        echo "(no dynamic rules active)"
    fi
}

# ---- threat feed: FireHOL level1 (dshield + feodo + fullbogons + spamhaus_drop) ----
# Managed sets use a "feed_" prefix so the WebUI can tell them apart from
# sets you created by hand. The firewall rule for a feed set is just a
# normal rule-add/rule-del on its name - no special-casing needed there.
#
# level1 bundles multiple malicious-infrastructure sources, but it also
# includes IANA "fullbogons" ranges (RFC 6890 special-purpose blocks) meant
# for ingress filtering at a network edge - NOT for outbound blocking on a
# client device. Blocking these here would break the device's own LAN
# gateway (192.168.0.0/16), carrier-grade NAT on mobile data (100.64.0.0/10),
# loopback (127.0.0.0/8), and a large chunk of multicast/reserved space
# (224.0.0.0/3). These are fixed, permanently-reserved ranges (they don't
# change), so they're excluded by exact-line match below - the malicious
# entries from every source (dshield/feodo/spamhaus_drop) are unaffected.

FEED_URL="https://raw.githubusercontent.com/firehol/blocklist-ipsets/refs/heads/master/firehol_level1.netset"
FEED_SET="feed_firehol_level1"
FEED_META="$DATA/feed_firehol_level1.meta"

cmd_feed_update() {
    DL=""
    if command -v curl >/dev/null 2>&1; then DL="curl -fsSL"
    elif command -v wget >/dev/null 2>&1; then DL="wget -qO-"
    fi
    [ -z "$DL" ] && die "neither curl nor wget found on this device - cannot download feed"

    echo "Fetching $FEED_URL ..."
    raw=$($DL "$FEED_URL" 2>&1) || die "download failed: $raw"
    [ -z "$raw" ] && die "download returned empty response"

    # fixed IANA special-purpose ranges (RFC 6890) - never change, safe to
    # hardcode. Excluded so this feed can never block the device's own LAN
    # gateway, carrier NAT, loopback, or reserved/multicast space.
    exclude_file="$DATA/feed_bogon_exclude.tmp"
    cat > "$exclude_file" << 'BOGONS'
0.0.0.0/8
10.0.0.0/8
100.64.0.0/10
127.0.0.0/8
169.254.0.0/16
172.16.0.0/12
192.0.0.0/24
192.0.2.0/24
192.168.0.0/16
198.18.0.0/15
198.51.100.0/24
203.0.113.0/24
224.0.0.0/3
BOGONS

    # strip comments/trailing-comment text and blank lines, drop the fixed
    # bogon ranges above by exact match, then sort+dedup in case the source
    # (which merges several upstream lists) contains any overlapping entries
    cidrs=$(echo "$raw" \
        | sed 's/#.*//' \
        | sed 's/[[:space:]]*$//' \
        | grep -v '^$' \
        | grep -vFx -f "$exclude_file" \
        | sort -u)
    rm -f "$exclude_file"

    parsed_count=$(echo "$cidrs" | grep -c .)
    [ "$parsed_count" -lt 1 ] && die "no CIDR entries parsed - feed format may have changed upstream"

    echo "Parsed $parsed_count entries from source (after bogon exclusion + dedup). Building set..."
    tmp="${FEED_SET}_tmp"
    "$IPSET" destroy "$tmp" 2>/dev/null
    "$IPSET" create "$tmp" hash:net -exist maxelem 65536 || die "failed to create temp set"

    batch="$DATA/feed_batch.tmp"
    : > "$batch"
    echo "$cidrs" | while read -r c; do
        [ -n "$c" ] && echo "add $tmp $c -exist" >> "$batch"
    done
    "$IPSET" restore -exist < "$batch" 2>&1 || die "ipset restore failed - batch may contain a malformed entry, or the upstream feed format changed"
    rm -f "$batch"

    # guard against a partial/failed restore silently wiping the live feed:
    # ipset restore can exit 0 while having applied only some of the batch
    # (or the tmp set can simply be empty if something upstream went wrong
    # earlier without tripping the check above) - never swap an empty/near-
    # empty result over a working set. 100 is a sanity floor well below any
    # real firehol_level1 pull, just catching "basically nothing loaded".
    tmp_count=$("$IPSET" list "$tmp" 2>/dev/null | grep "^Number of entries:" | awk '{print $NF}')
    [ -z "$tmp_count" ] && tmp_count=0
    if [ "$tmp_count" -lt 100 ]; then
        "$IPSET" destroy "$tmp" 2>/dev/null
        die "ipset restore produced only $tmp_count entries (expected thousands) - aborting, existing feed left untouched"
    fi

    # atomic swap: the old set's members are fully discarded here (destroyed
    # under the tmp name after swap) - every update is a clean full
    # replacement, never a merge of old+new entries
    if "$IPSET" list -n 2>/dev/null | grep -qx "$FEED_SET"; then
        "$IPSET" swap "$tmp" "$FEED_SET" || die "swap failed"
        "$IPSET" destroy "$tmp"
    else
        "$IPSET" rename "$tmp" "$FEED_SET" || die "rename failed"
    fi
    own_add "$FEED_SET"

    # report the real, de-duplicated member count from the live set - not the
    # raw source line count, which can be a few entries higher if the feed
    # contains overlapping/duplicate CIDRs (ipset silently merges those)
    real_count=$("$IPSET" list "$FEED_SET" 2>/dev/null | grep "^Number of entries:" | awk '{print $NF}')
    [ -z "$real_count" ] && real_count=$tmp_count

    echo "{\"updated\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"count\":$real_count,\"source\":\"$FEED_URL\"}" > "$FEED_META"
    cmd_save
    log "feed updated: $FEED_SET ($real_count entries, $parsed_count in source)"
    echo "OK: $FEED_SET updated with $real_count entries"
}

cmd_feed_status() {
    if [ -f "$FEED_META" ]; then
        cat "$FEED_META"
    else
        echo "(never updated)"
    fi
}

cmd_save() {
    # `ipset save` with no argument dumps EVERY set on the device.
    # Save ours one at a time instead, so the state file can never
    # pick up a set belonging to another app - which would then be
    # restored at boot, and destroyed by flush-all, as if it were ours.
    : > "${STATE}.tmp"
    own_list | while read -r n; do
        [ -z "$n" ] && continue
        "$IPSET" save "$n" >> "${STATE}.tmp" 2>/dev/null
    done
    mv "${STATE}.tmp" "$STATE"
    log "state saved ($(wc -l < "$STATE" 2>/dev/null || echo 0) lines, $(own_list | grep -c . 2>/dev/null || echo 0) owned set(s))"
}

cmd_restore() {
    echo "== restore run: $(date '+%Y-%m-%d %H:%M:%S') =="

    if [ -s "$STATE" ]; then
        entries=$(grep -c '^add ' "$STATE" 2>/dev/null)
        sets=$(grep -c '^create ' "$STATE" 2>/dev/null)
        echo "Restoring $sets set(s), $entries entr(y/ies) from $STATE"
        # -exist: a set may already be present (an earlier boot script,
        # a manual create, a re-run of this command). Without it, ipset
        # restore aborts on the first collision and everything after
        # that line is silently not restored.
        out=$("$IPSET" restore -exist < "$STATE" 2>&1)
        [ -n "$out" ] && echo "$out"
        echo "Sets restored."
        log "sets restored from $STATE"
    else
        echo "No saved sets found ($STATE empty or missing) - nothing to restore."
        log "no saved state to restore"
    fi

    if [ -s "$RULES" ]; then
        count=0
        while IFS='|' read -r chain name dir target uid; do
            [ -z "$chain" ] && continue
            owner_args=""
            [ -n "$uid" ] && owner_args="-m owner --uid-owner $uid"
            "$IPTABLES" -C "$chain" $owner_args -m set --match-set "$name" "$dir" -j "$target" 2>/dev/null
            if [ $? -ne 0 ]; then
                "$IPTABLES" -I "$chain" $owner_args -m set --match-set "$name" "$dir" -j "$target" 2>&1
                echo "Rule restored: $chain, match-set $name $dir, -j $target${uid:+ (app uid $uid)}"
                log "rule restored: $chain|$name|$dir|$target${uid:+|$uid}"
            else
                echo "Rule already active: $chain, match-set $name $dir, -j $target${uid:+ (app uid $uid)}"
            fi
            count=$((count + 1))
        done < "$RULES"
        echo "$count rule(s) checked/restored."
    else
        echo "No saved rules found - nothing to reapply."
    fi

    echo "== restore complete =="
}

cmd_types() {
    echo "Set types supported by this script:"
    echo "  bitmap:ip        bitmap:ip,mac    bitmap:port"
    echo "  hash:ip          hash:mac         hash:ip,mac"
    echo "  hash:net         hash:net,net     hash:net,port"
    echo "  hash:net,port,net                 hash:net,iface"
    echo "  hash:ip,port     hash:ip,port,ip  hash:ip,port,net"
    echo "  hash:ip,mark     list:set"
    echo ""
    echo "Usage: create <name> [type] [inet|inet6]     (default type: hash:ip)"
    echo "Examples:"
    echo "  create blocklist hash:net"
    echo "  create v6block   hash:net inet6"
    echo "  create devices   hash:mac"
    echo ""
    echo "Which types actually work depends on the kernel - run 'status'."
}

cmd_bootlog() {
    if [ -s "$DATA/service.log" ]; then
        cat "$DATA/service.log"
    else
        echo "(no boot log yet - reboot the device once to generate it)"
    fi
}

cmd_bootlog_clear() {
    : > "$DATA/service.log"
    log "boot log cleared manually"
    echo "OK: boot log cleared"
}

cmd_flush_all() {
    if [ -s "$RULES" ]; then
        while IFS='|' read -r chain name dir target uid; do
            [ -z "$chain" ] && continue
            owner_args=""
            [ -n "$uid" ] && owner_args="-m owner --uid-owner $uid"
            "$IPTABLES" -D "$chain" $owner_args -m set --match-set "$name" "$dir" -j "$target" 2>/dev/null
        done < "$RULES"
    fi
    : > "$RULES"
    _destroyed=0
    own_list | while read -r n; do
        [ -z "$n" ] && continue
        "$IPSET" destroy "$n" 2>/dev/null
    done
    _destroyed=$(own_list | grep -c . 2>/dev/null || echo 0)
    : > "$OWNED"
    cmd_save
    log "flush-all executed ($_destroyed set(s))"
    echo "OK: removed $_destroyed set(s) created by this module, and all its rules"
    echo "    (sets created by other apps were left alone)"
}

# ---- dispatch ----

case "${1:-}" in
    status)    cmd_status ;;
    list)      cmd_list "${2:-}" ;;
    create)    cmd_create "${2:-}" "${3:-}" "${4:-}" ;;
    types)     cmd_types ;;
    owned)     own_list ;;
    destroy)   cmd_destroy "${2:-}" ;;
    add)       shift; cmd_add "$@" ;;
    del)       shift; cmd_del "$@" ;;
    test)      cmd_test "${2:-}" "${3:-}" ;;
    rule-add)  cmd_rule_add "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" ;;
    rule-del)  cmd_rule_del "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" ;;
    apps)      cmd_apps ;;
    rules)     cmd_rules ;;
    bootlog)   cmd_bootlog ;;
    bootlog-clear) cmd_bootlog_clear ;;
    feed-update) cmd_feed_update ;;
    feed-status) cmd_feed_status ;;
    save)      cmd_save ;;
    restore)   cmd_restore ;;
    flush-all) cmd_flush_all ;;
    *)
        echo "Usage: ipctl.sh {status|types|list|owned|create|destroy|add|del|test|"
        echo "                 rule-add|rule-del|rules|apps|bootlog|bootlog-clear|"
        echo "                 feed-update|feed-status|save|restore|flush-all}"
        exit 1
        ;;
esac
