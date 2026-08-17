# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=uz801-leds
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=UZ801 LED controller
	DEPENDS:=+qmi-utils
	PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
	LED configuration for YiMing UZ801 v3.
	Controls WLAN, LTE/WAN and Power LEDs.
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/uz801-leds.init $(1)/etc/init.d/uz801-leds

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/uz801-led-monitor.sh \
		$(1)/usr/sbin/uz801-led-monitor

	$(INSTALL_DIR) $(1)/etc/rc.d
	$(LN) ../init.d/uz801-leds $(1)/etc/rc.d/S99uz801-leds
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
