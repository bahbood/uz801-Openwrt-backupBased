include $(TOPDIR)/rules.mk

PKG_NAME:=zhihe-qmi
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/zhihe-qmi
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Custom QMI protocol for Zhihe/Yiming MSM8916 modems
  DEPENDS:=+libqmi +qmi-utils
  CONFLICTS:=modemmanager
  PKGARCH:=all
endef

define Package/zhihe-qmi/description
  A custom netifd protocol handler for buggy MSM8916 LTE dongles
  that crash with standard ModemManager or uqmi.
endef

define Build/Compile
endef

define Package/zhihe-qmi/install
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/zhiheqmi.sh $(1)/lib/netifd/proto/zhiheqmi.sh
endef

$(eval $(call BuildPackage,zhihe-qmi))