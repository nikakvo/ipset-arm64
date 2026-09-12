#!/system/bin/sh
# uninstall.sh - runs while the module directory still exists, before removal.
# Goal: leave the device exactly as if this module was never installed -
# no orphaned ipset sets, no orphaned iptables rules, no leftover data.

MODDIR=${0%/*}

ui_print() { echo "$1"; }

ui_print "- Removing ipset-arm64: flushing all dynamic sets and firewall rules"

if [ -f "$MODDIR/ipctl.sh" ]; then
    sh "$MODDIR/ipctl.sh" flush-all >/dev/null 2>&1
    ui_print "  - dynamic state flushed via ipctl.sh"
else
    ui_print "  - ipctl.sh missing, falling back to manual cleanup"

    IPSET="$MODDIR/system/bin/ipset"
    [ -x "$IPSET" ] || IPSET="$(command -v ipset 2>/dev/null)"
    IPTABLES="$(command -v iptables 2>/dev/null || echo /system/bin/iptables)"

    if [ -x "$IPSET" ] && [ -s "/data/adb/ipset_arm64_data/rules.conf" ]; then
        while IFS='|' read -r chain name dir target uid; do
            [ -z "$chain" ] && continue
            owner_args=""
            [ -n "$uid" ] && owner_args="-m owner --uid-owner $uid"
            "$IPTABLES" -D "$chain" $owner_args -m set --match-set "$name" "$dir" -j "$target" 2>/dev/null
        done < "/data/adb/ipset_arm64_data/rules.conf"
    fi

    # Only destroy sets THIS MODULE created, listed in owned.list.
    # This used to iterate `ipset list -n`, i.e. every set on the
    # device - so uninstalling this module deleted the firewall state
    # of any other app using ipset. If the manifest is missing there is
    # nothing we can prove ownership of, so nothing is destroyed.
    OWNED="/data/adb/ipset_arm64_data/owned.list"
    if [ -x "$IPSET" ] && [ -s "$OWNED" ]; then
        while read -r n; do
            [ -z "$n" ] && continue
            "$IPSET" destroy "$n" 2>/dev/null
        done < "$OWNED"
    elif [ -x "$IPSET" ]; then
        ui_print "  - no ownership manifest found; leaving all ipset sets in place"
    fi
fi

# Persisted data lives outside $MODDIR (see ipctl.sh) so it survives
# module updates - Magisk/KernelSU only remove $MODDIR itself, so we
# have to remove this external directory ourselves on uninstall.
if [ -d "/data/adb/ipset_arm64_data" ]; then
    rm -rf "/data/adb/ipset_arm64_data"
    ui_print "  - removed persisted data (/data/adb/ipset_arm64_data)"
fi

ui_print "- ipset-arm64 removed cleanly"
