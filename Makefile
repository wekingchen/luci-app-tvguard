include $(TOPDIR)/rules.mk

LUCI_TITLE:=TV Guard - 家庭电视时间管理
LUCI_DESCRIPTION:=LuCI UI and lightweight time-control daemon for firewall3 routers
LUCI_DEPENDS:=+luci-base +rpcd +curl
LUCI_PKGARCH:=all
PKG_LICENSE:=MIT
PKG_RELEASE:=1

include $(TOPDIR)/feeds/luci/luci.mk
