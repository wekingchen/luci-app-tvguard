include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-tvguard
PKG_VERSION:=0.1.16
PKG_RELEASE:=26
PKG_LICENSE:=MIT
PKG_MAINTAINER:=TV Guard contributors

# package.mk is required: luci.mk ignores our former custom prepare hook
# and can override the lifecycle hooks necessary for the integrated Bridge.
include $(INCLUDE_DIR)/package.mk

define Package/luci-app-tvguard
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=TV Guard - 家庭电视时间管理
  DEPENDS:=+luci-base +rpcd +curl +uhttpd +jsonfilter
  PKGARCH:=all
  CONFLICTS:=tvguard-agent-bridge
  PROVIDES:=tvguard-agent-bridge
endef

define Package/luci-app-tvguard/description
  LuCI UI, policy daemon, parent remote, and integrated TV Agent Bridge
  for firewall3 / iptables-legacy OpenWrt routers.
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/root $(PKG_BUILD_DIR)/htdocs
	$(CP) ./root/. $(PKG_BUILD_DIR)/root/
	$(CP) ./htdocs/. $(PKG_BUILD_DIR)/htdocs/
	sh ./scripts/stage-openwrt-native.sh "$(CURDIR)" "$(PKG_BUILD_DIR)"
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-tvguard/install
	$(INSTALL_DIR) $(1)/www
	$(CP) $(PKG_BUILD_DIR)/root/. $(1)/
	$(CP) $(PKG_BUILD_DIR)/htdocs/. $(1)/www/
endef

# One source of truth: exactly the same opkg scripts as scripts/build-ipk.sh.
# GNU make's file-read function retains the original shell syntax and newlines.
define Package/luci-app-tvguard/conffiles
$(file <$(CURDIR)/ipkg/conffiles)
endef

define Package/luci-app-tvguard/preinst
$(file <$(CURDIR)/ipkg/preinst)
endef

define Package/luci-app-tvguard/postinst
$(file <$(CURDIR)/ipkg/postinst)
endef

define Package/luci-app-tvguard/prerm
$(file <$(CURDIR)/ipkg/prerm)
endef

$(eval $(call BuildPackage,luci-app-tvguard))
