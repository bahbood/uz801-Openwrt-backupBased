include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI UZ801 CPU Management
LUCI_DEPENDS:=+rpcd
LUCI_PKGARCH:=all
PKG_LICENSE:=GPL-2.0-only

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-uz801-cpu/install
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/uz801_cpu $(1)/usr/libexec/rpcd/uz801_cpu
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/uz801-cpu $(1)/etc/init.d/uz801-cpu
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/uz801cpu $(1)/etc/config/uz801cpu
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-uz801-cpu.json $(1)/usr/share/luci/menu.d/luci-app-uz801-cpu.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-uz801-cpu.json $(1)/usr/share/rpcd/acl.d/luci-app-uz801-cpu.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/uz801_cpu
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/uz801_cpu/main.js $(1)/www/luci-static/resources/view/uz801_cpu/main.js
endef

define Package/luci-app-uz801-cpu/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/uz801-cpu enable
	/etc/init.d/uz801-cpu apply >/dev/null 2>&1 || true
	/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-uz801-cpu))
