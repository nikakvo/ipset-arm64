# ipset-arm64

Statically-linked `ipset` binary for Android (arm64), packaged as a systemless Magisk/KernelSU/APatch module — **now with a full dynamic control layer and WebUI**, not just the raw binary.

`ipset` is not included in AOSP/GKI userspace by default. This module provides the missing userspace tool for devices whose kernel already has `CONFIG_IP_SET` compiled in (check with `zcat /proc/config.gz | grep IP_SET` or `cat /proc/net/ip_tables_matches | grep set`), plus everything needed to actually *use* it without touching a terminal.


## What is ipset?

`ipset` lets you group IP addresses, networks, MAC addresses, and ports into named **sets**, which `iptables`/`ip6tables` can then match against with a single rule instead of one rule per address.

Benefits over plain iptables rules:
- **O(1) hash-based lookups** instead of linear rule-by-rule scanning
- **Dynamic updates** — add/remove addresses from a set without touching or reloading the firewall ruleset
- Cleaner, shorter iptables rulesets when dealing with large address lists

Typical uses: blocking a known-bad server by IP, blocking an entire hosting range (CIDR) that keeps serving abuse traffic, cutting off an app that ignores your DNS settings and connects straight to a hardcoded IP, or building a personal blocklist of ad/telemetry endpoints.

## Requirements

- Root (Magisk, KernelSU, SukiSU-Ultra, APatch, or any compatible fork)
- Kernel with `CONFIG_IP_SET=y` (or relevant `m` modules loaded)
- `iptables` with `xt_set` match/target support (`CONFIG_NETFILTER_XT_SET=y`)
- A manager with WebUI support (KernelSU Next, SukiSU-Ultra Manager, or any MMRL-compatible manager) to use the control panel — the raw `ipctl.sh` commands work with any manager regardless of WebUI support

## Installation

1. Download the latest release zip from [Releases](../../releases)
2. Flash via your root manager's module installer (Magisk Manager / KernelSU Manager / SukiSU-Ultra Manager → Modules → Install from storage)
3. Reboot
4. Open the module's WebUI from your manager (or verify manually: `su -c ipset -v`)

<img width="300" alt="ipset-arm64" src="https://raw.githubusercontent.com/nikakvo/ipset-arm64/refs/heads/main/ipset-arm64.jpg" />

## Usage

### Via the WebUI (recommended)

Open the module from your manager's WebUI list. The control panel walks you through:

1. **Status** — confirms your kernel actually supports ipset before you do anything else
2. **Sets** — create a set, choose `hash:ip` (single addresses) or `hash:net` (CIDR ranges)
3. **Set Detail** — add/remove addresses, toggle the firewall rule on or off
4. **Active Rules** — see everything currently being enforced, at a glance
5. **Connectivity Test** — built-in ping, to confirm a block actually took effect
6. **Boot Restore Log** — what got reloaded on the last boot
7. **Command Log** — session history of every action taken

Tap **HELP** in the control panel for the full walkthrough with example commands for each section.

### Via shell (adb / Termux, `su`)

```sh
sh /data/adb/modules/ipset_arm64/ipctl.sh create myservers hash:ip
sh /data/adb/modules/ipset_arm64/ipctl.sh add myservers 1.2.3.4
sh /data/adb/modules/ipset_arm64/ipctl.sh add myservers 5.6.7.8
sh /data/adb/modules/ipset_arm64/ipctl.sh rule-add myservers   # OUTPUT dst DROP by default
```

Full command reference (`status`, `list`, `create`, `destroy`, `add`, `del`, `test`, `rule-add`, `rule-del`, `rules`, `bootlog`, `save`, `restore`, `flush-all`) is in `webroot/help.html`, section 11.

### Raw ipset/iptables (bypassing the control layer entirely)

Still works exactly as before, if you'd rather manage things yourself:

```bash
su -c "ipset create myservers hash:ip"
su -c "ipset add myservers 1.2.3.4"
su -c "iptables -A OUTPUT -m set --match-set myservers dst -j DROP"
```

Note: sets/rules created this way are **not** tracked by `ipctl.sh` and won't be included in its persistence, status output, or `flush-all` cleanup.

## Persistence

Sets and rules are saved to `/data/adb/ipset_arm64_data/` — deliberately outside the module's own directory. Magisk/KernelSU replace a module's entire folder on update, so anything stored inside it would be lost every time you reflash. Storing state externally means updating to a newer release of this module doesn't touch your existing configuration; `service.sh` reapplies it automatically on every boot.

## Uninstalling

Removing the module through your manager's normal uninstall flow runs `uninstall.sh`, which removes every rule and set this module created (at the kernel level, not just files) and deletes the external data directory. Nothing is left running after the module is gone.

## Using this alongside dnscrypt-proxy-android-arm64-only

[dnscrypt-proxy-android-arm64-only](https://github.com/nikakvo/dnscrypt-proxy-android-arm64-only) is a companion module that filters at the **DNS layer** (blocking by domain name, before an IP is even resolved). This module filters at the **IP/packet layer** (blocking by address, after an IP is known). They don't compete for the same traffic and are safe to run together — dnscrypt-proxy catches known-bad domains cheaply and broadly; ipset-arm64 catches what DNS filtering can't, like apps with hardcoded IPs that bypass your resolver entirely. See `webroot/help.html` section 10 for details.

## Build details

- Cross-compiled with Android NDK (aarch64-linux-android, API 29)
- Statically linked against `libmnl` (netlink communication library)
- Dynamically linked against Android's bionic libc/libdl (standard for NDK-built binaries — full static linking is not supported on Android)
- Built from upstream sources: [ipset](https://git.netfilter.org/ipset) ([GitHub mirror](https://github.com/Olipro/ipset)) + [libmnl](https://git.netfilter.org/libmnl) ([GitHub mirror](https://github.com/Distrotech/libmnl))

## Version compatibility

This binary speaks **ipset protocol version 7**. It communicates with the kernel's `IP_SET` netlink interface, so it will work with any GKI kernel that has `CONFIG_IP_SET` enabled, regardless of Android version, as long as the kernel-side protocol version matches (all modern GKI kernels currently use protocol v7).

## Disclaimer

Provided as-is, for testing and personal use. Not affiliated with the upstream ipset/netfilter project. Use at your own risk — always keep a backup.
