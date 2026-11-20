# TVGuard native OpenWrt/LEDE firmware package

The native Makefile uses OpenWrt package.mk to stage the same LuCI,
daemon, remote and integrated Agent Bridge files as scripts/build-ipk.sh.
It imports preinst/postinst/prerm/conffiles directly from ipkg/, preventing
maintenance of separate package lifecycle scripts. The former
Build/Prepare/luci-app-tvguard hook (ignored by luci.mk) was removed.

Only native image packages add a late one-shot bootstrap service and an
uci-defaults hook. Image builds set IPKG_INSTROOT and must not execute runtime
postinst. At boot, uci-defaults enables tvguard-native-bootstrap (START=94).
After /mnt/mmcblk2p4 is mounted, this runs an exact staged copy of the normal
postinst, enabling core, Agent Bridge, remote watchdog, and restoring config.
Successful initialization disables the bootstrap service. Missing XFS
defers initialization, without writing a substitute persistent database.
Normal opkg install runs postinst immediately, and removes the unused
native uci-defaults script.

No XFS data, device tokens, pairing keys, or user-specific configuration
are ever compiled into the firmware.

## Validation

Host-side:
  sh scripts/build-ipk.sh 0.1.16 26
  python3 tests/test-native-openwrt-package.py

LEDE integration, after adding the source to package/luci-app-tvguard:
  make defconfig
  make package/luci-app-tvguard/compile V=s

Verify the resulting IPK control metadata, script hooks, executable bits,
and firmware rootfs manifest. N1 real-boot acceptance remains required:
check XFS mount readiness, tvguard status, isolation audit, Bridge, parent
remote/watchdog, and existing persisted settings/pairing after a reflash.
Host-side parity tests are not proof of a full LEDE build or N1 boot.
