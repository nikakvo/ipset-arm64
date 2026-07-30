# ipset-arm64

Standalone, statically-linked `ipset` binary for Android (arm64), packaged as a systemless Magisk/KernelSU/APatch module.

`ipset` is not included in AOSP/GKI userspace by default. This module provides the missing userspace tool for devices whose kernel already has `CONFIG_IP_SET` compiled in (check with `zcat /proc/config.gz | grep IP_SET` or `cat /proc/net/ip_tables_matches | grep set`).

## What is ipset?

`ipset` lets you group IP addresses, networks, MAC addresses, and ports into named **sets**, which `iptables`/`ip6tables` can then match against with a single rule instead of one rule per address.

Benefits over plain iptables rules:
- **O(1) hash-based lookups** instead of linear rule-by-rule scanning
- **Dynamic updates** — add/remove addresses from a set without touching or reloading the firewall ruleset
- Cleaner, shorter iptables rulesets when dealing with large address lists

## Requirements

- Root (Magisk, KernelSU, SukiSU-Ultra, APatch, or any compatible fork)
- Kernel with `CONFIG_IP_SET=y` (or relevant `m` modules loaded)
- `iptables` with `xt_set` match/target support (`CONFIG_NETFILTER_XT_SET=y`)

## Installation

1. Download the latest release zip from [Releases](../../releases)
2. Flash via your root manager's module installer (Magisk Manager / KernelSU Manager / SukiSU-Ultra Manager → Modules → Install from storage)
3. Reboot
4. Verify:
   ```
   su -c ipset -v
   ```

## Usage example

```bash
su -c "ipset create myservers hash:ip"
su -c "ipset add myservers 1.2.3.4"
su -c "ipset add myservers 5.6.7.8"
su -c "iptables -A OUTPUT -m set --match-set myservers dst -j MARK --set-mark 1"
```

## Build details

- Cross-compiled with Android NDK (aarch64-linux-android, API 29)
- Statically linked against `libmnl` (netlink communication library)
- Dynamically linked against Android's bionic libc/libdl (standard for NDK-built binaries — full static linking is not supported on Android)
- Built from upstream sources: [ipset](https://git.netfilter.org/ipset) ([GitHub mirror](https://github.com/Olipro/ipset)) + [libmnl](https://git.netfilter.org/libmnl) ([GitHub mirror](https://github.com/Distrotech/libmnl))

## Version compatibility

This binary speaks **ipset protocol version 7**. It communicates with the kernel's `IP_SET` netlink interface, so it will work with any GKI kernel that has `CONFIG_IP_SET` enabled, regardless of Android version, as long as the kernel-side protocol version matches (all modern GKI kernels currently use protocol v7).

## Disclaimer

Provided as-is, for testing and personal use. Not affiliated with the upstream ipset/netfilter project. Use at your own risk — always keep a backup.
