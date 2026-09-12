#!/system/bin/sh
ui_print "- Installing ipset binary"
set_perm_recursive $MODPATH/system/bin 0 0 0755 0755

ui_print "- Setting up ipctl.sh and service.sh"
set_perm $MODPATH/ipctl.sh 0 0 0755
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/uninstall.sh 0 0 0755

# start fresh on every install/upgrade - the boot-restore log is meant to
# answer "what did the last boot do", not carry history across module
# versions (service.sh already clears it on every boot; this covers the
# gap between flashing and the first reboot)
ui_print "- Clearing previous boot-restore log"
DATA="/data/adb/ipset_arm64_data"
mkdir -p "$DATA"
: > "$DATA/service.log"
