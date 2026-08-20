# Changelog

All notable changes to this module are documented here.

---

## v7.24-r2

### Added
- **`ipctl.sh`** — dynamic control engine for the module. Nothing is static or default-enabled: sets, addresses, and firewall rules only exist once explicitly created. Commands: `status`, `list`, `create`, `destroy`, `add`, `del`, `test`, `rule-add`, `rule-del`, `rules`, `bootlog`, `save`, `restore`, `flush-all`.
- **WebUI control panel** (`webroot/index.html`) — create/destroy sets, manage members, toggle firewall rules, run a built-in connectivity (ping) test, and review logs, entirely from your root manager's WebUI. No Termux or adb required for day-to-day use.
- **In-app help** (`webroot/help.html`) — full documentation covering every panel, `hash:ip` vs `hash:net`, persistence/update behavior, uninstall behavior, and how to use this module alongside `dnscrypt-proxy-android-arm64-only`.
- **`service.sh`** — automatically restores all sets and firewall rules on every boot. Purely reactive: if nothing was ever created, it does nothing.
- **External persistent storage** (`/data/adb/ipset_arm64_data/`) — sets and rules now survive both reboots **and** module updates/reflashes, since this location lives outside the folder Magisk/KernelSU replace on update. Includes automatic one-time migration from the old in-module storage path for anyone upgrading from an earlier internal build.
- **`uninstall.sh`** — full cleanup on module removal: flushes every ipset set and iptables rule the module created (kernel-level, not just files) and deletes the external data directory. No orphaned rules left active after uninstall.
- **Boot Restore Log** — visibility into exactly what `service.sh` restored on the last boot, viewable directly in the WebUI.
- **Command Log** — rolling session history (last 30 actions) of everything run through the WebUI, with a live size indicator.
- **Connectivity Test panel** — built-in ping runner to verify a block took effect, without leaving the WebUI.
- **Status panel** — live kernel capability check (`CONFIG_IP_SET`, `CONFIG_IP_SET_HASH_IP`, `CONFIG_IP_SET_HASH_NET`, `CONFIG_NETFILTER_XT_SET`, `xt_set` match), plus a snapshot of every active set and rule, with color-coded terminal-style output (green = OK, red = missing/failed).
- **Cascading set deletion** — "Delete entire set" in the WebUI now automatically disables any active rule referencing it first, then destroys it, instead of blocking with an error.

### Changed
- `customize.sh` now sets executable permissions on `ipctl.sh`, `service.sh`, and `uninstall.sh` explicitly, independent of how permission bits survive zip packaging.

### Fixed
- Rule removal (`rule-del`) no longer silently fails to update `rules.conf` when it was the only active rule for a set — a POSIX `grep -v` exit-code trap (empty output = non-zero exit) could previously leave a stale "active" entry in the tracking file even after the underlying iptables rule was correctly removed.

---

## v7.24-r1 (Initial Release)

- First public build of `ipset` v7.24 for Android arm64
- Cross-compiled with Android NDK r26d, targeting aarch64-linux-android API 29
- Statically linked against libmnl
- Tested against GKI 5.15.194 (android13-5.15) kernel with `CONFIG_IP_SET=y`
- Confirmed working: set creation, add/list/destroy operations, protocol v7 handshake with kernel
