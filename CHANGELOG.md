# Changelog

All notable changes to this module are documented here.

## ipset-arm64-v7.24-r3

### Added
- **Config section (03) redesigned into 3 independent rule slots per set** — supports up to 3 simultaneous firewall rules on the same set (e.g. block both `INPUT` and `OUTPUT` at once, or apply different targets per direction). Each slot tracks its own identity across refreshes; enabling slot 2 stays in slot 2, never gets reshuffled to slot 1.
- **Config is now fully decoupled from Set Detail** — has its own independent set selector, separate from tapping a tile in Sets. Managing rules never requires scrolling past a set's member list, no matter how large (tested against a 1600+ entry feed set).
- **Set Detail (member editor) repositioned** directly under Sets, accordion-style — tap a tile to open, tap again to close, no page navigation needed.
- **Duplicate rule prevention** — attempting to enable a chain/direction/target combination already active in another slot is blocked with an on-screen warning instead of silently creating a redundant tracking entry.
- **Threat Feeds panel (06)** — new managed set `feed_spamhaus_drop`, sourced from [Spamhaus DROP v4](https://www.spamhaus.org/drop/drop_v4.json). "Update Now" for manual refresh (atomic swap, zero traffic gap), "Enable auto (24h)" toggle for background refresh every 24 hours (resumes automatically after reboot if left on, off by default). Feed-managed sets are tagged with an orange **FEED** badge in the Sets list.
- `ipctl.sh` gained three commands: `feed-update`, `feed-status`, `feed-auto {on|off|status}`.
- `service.sh` resumes the threat feed auto-update loop after reboot if it was previously enabled.
- `uninstall.sh` now also stops the threat feed auto-update loop and removes its state on module removal.
- **HELP badge** added to the WebUI header, linking directly to in-app documentation.
- `webroot/help.html` fully rewritten to match the new architecture: Config's 3-slot system, Threat Feeds, corrected section numbering throughout, expanded command reference.

### Changed
- **Clear** (Command Log) button restyled red to match other destructive actions; **Refresh** buttons restyled cyan for visual consistency with other read/info actions.
- Command reference docs now cover multi-rule usage (calling `rule-add` again with a different chain/direction to stack up to 3 rules on one set).

### Fixed
- **Config slot reassignment bug** — activating a specific rule slot (e.g. slot 2) could cause a *different* slot (e.g. slot 1) to display as active instead, because slot contents were recalculated positionally from the rules list on every refresh rather than tracking which slot the user actually interacted with. Slot identity is now tracked persistently and independently across refreshes.

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
