# Changelog

## v7.24-r1 (Initial Release)

- First public build of `ipset` v7.24 for Android arm64
- Cross-compiled with Android NDK r26d, targeting aarch64-linux-android API 29
- Statically linked against libmnl
- Tested against GKI 5.15.194 (android13-5.15) kernel with `CONFIG_IP_SET=y`
- Confirmed working: set creation, add/list/destroy operations, protocol v7 handshake with kernel
