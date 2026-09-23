#!/system/bin/sh
# uninstall.sh - leave the device as if the module was never installed:
# no chains, no jumps, no sets of ours, no data. Sets and rules that belong
# to other apps are never touched.

MODDIR=${0%/*}
DATA_DIR="/data/adb/ipset_arm64_data"

if [ -f "$MODDIR/sh/common.sh" ]; then
  # shellcheck source=/dev/null
  . "$MODDIR/sh/common.sh"
  lock_get 20
  # Chains and jumps first: a set still referenced by a rule cannot be destroyed.
  rules_remove_all
  sets_destroy_managed
  sources_destroy_all
  for _n in $(own_list); do "$IPSET" destroy "$_n" 2>/dev/null; done
  lock_release
else
  # Incomplete module: remove what can be removed by name.
  for _t in iptables ip6tables; do
    command -v "$_t" >/dev/null 2>&1 || continue
    for _j in OUTPUT:IPSA_OUT INPUT:IPSA_IN FORWARD:IPSA_FWD; do
      while "$_t" -w -D "${_j%%:*}" -j "${_j#*:}" 2>/dev/null; do :; done
    done
    for _c in IPSA_OUT IPSA_IN IPSA_FWD IPSA_ADV_OUT IPSA_ADV_IN IPSA_ADV_FWD; do "$_t" -w -F "$_c" 2>/dev/null; done
    for _c in IPSA_OUT IPSA_IN IPSA_FWD IPSA_ADV_OUT IPSA_ADV_IN IPSA_ADV_FWD; do "$_t" -w -X "$_c" 2>/dev/null; done
  done
  _ipset="$MODDIR/system/bin/ipset"
  [ -x "$_ipset" ] || _ipset=$(command -v ipset 2>/dev/null)
  if [ -n "$_ipset" ]; then
    for _s in $("$_ipset" list -n 2>/dev/null | grep -E '^ipsa_(out|in|block)[46]'); do "$_ipset" destroy "$_s" 2>/dev/null; done
    for _s in $("$_ipset" list -n 2>/dev/null | grep '^ipsa_'); do "$_ipset" destroy "$_s" 2>/dev/null; done
    for _s in $("$_ipset" list -n 2>/dev/null | grep '^ipsa_'); do "$_ipset" destroy "$_s" 2>/dev/null; done
    [ -s "$DATA_DIR/owned.list" ] && while read -r _s; do
      [ -n "$_s" ] && "$_ipset" destroy "$_s" 2>/dev/null
    done < "$DATA_DIR/owned.list"
  fi
fi

rm -rf "$DATA_DIR"
# The sdcard copies of your lists are yours; they are left in place.
