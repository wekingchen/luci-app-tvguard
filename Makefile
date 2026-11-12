include $(TOPDIR)/rules.mk

LUCI_TITLE:=TV Guard - 家庭电视时间管理
LUCI_DESCRIPTION:=LuCI UI and lightweight time-control daemon for firewall3 routers
LUCI_DEPENDS:=+luci-base +rpcd +curl +uhttpd
LUCI_PKGARCH:=all
PKG_LICENSE:=MIT
PKG_VERSION:=0.1.14
PKG_RELEASE:=5

# luci.mk only stages ./root by default. Merge the separately tested Bridge
# sources into that tree for OpenWrt-feed builds as well as script-built IPKs.
define Build/Prepare/luci-app-tvguard
	$(CP) ./bridge/root/* $(PKG_BUILD_DIR)/root/
	$(INSTALL_BIN) ./bridge/ipkg/postinst $(PKG_BUILD_DIR)/root/usr/libexec/tvguard-agent-bridge-setup
endef

include $(TOPDIR)/feeds/luci/luci.mk
