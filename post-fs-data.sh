#!/system/bin/sh
# post-fs-data.sh - early boot, before netd and before any app runs.
#
# Loads every set (the module's lists and your advanced sets) so they are
# ready long before the network is. No firewall rules here: netd flushes
# OUTPUT/INPUT/FORWARD when it starts, so service.sh adds the jumps once
# netd is done. This script must stay fast - post-fs-data blocks the boot.

MODDIR=${0%/*}
[ -f "$MODDIR/sh/common.sh" ] || exit 0
# shellcheck source=/dev/null
. "$MODDIR/sh/common.sh"

mkdir -p "$DATA"
rm -rf "$RUN"
mkdir -p "$RUN"
: > "$BOOTLOG"
load_settings
rotate_log

if [ -z "$IPSET" ] || ! "$IPSET" --version >/dev/null 2>&1; then
  bootlog "post-fs-data: ipset binary not runnable - nothing loaded"
  log_error "post-fs-data: ipset binary not runnable"
  exit 0
fi

lock_get 5 || exit 0
if user_sets_restore; then
  bootlog "post-fs-data: advanced sets restored ($(own_list | grep -c .) set(s))"
else
  bootlog "post-fs-data: some advanced sets could not be restored (see log)"
fi
if sets_ensure 1; then
  bootlog "post-fs-data: module sets ready (allowlist $(list_count allow), blocklist $(list_count user) entries)"
else
  bootlog "post-fs-data: some module sets could not be prepared (see log)"
fi
lock_release
exit 0
