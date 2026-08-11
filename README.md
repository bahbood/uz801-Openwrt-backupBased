# OpenWrt for UZ801 (backup-based / empty eMMC)

OpenWrt port for the **YiMing / FY UZ801 V3 / V3.2** USB 4G modem (Qualcomm MSM8916).

This fork is designed for the case where the device **eMMC is empty, corrupted, or not usable**, and all required radio/modem data must come from a **local factory firmware backup** instead of being read from the live device.

Based on the work of [hkfuertes/msm8916-openwrt](https://github.com/hkfuertes/msm8916-openwrt) and [ImMALWARE/uz801-openwrt](https://github.com/ImMALWARE/uz801-openwrt).

---

## Main differences of this fork

| Feature | Upstream | This fork |
|---------|----------|-----------|
| Modem firmware source | Dumped from device on first boot (`msm-firmware-dumper`) | Embedded in the image from a local backup |
| Radio / NV partitions (`fsc`, `fsg`, `modemst1`, `modemst2`) | Backed up from live device during flash | Taken from `stock-firmware-extract/radio/` |
| Assumption about eMMC | Stock or previously working firmware present | eMMC may be empty / unusable |
| ModemManager | Removed (crashes the modem) | Removed |
| Cellular stack | Custom `zhihe-qmi` + LuCI apps | Same |

---

## What is included

### Firmware embedded in the image
- Modem firmware (`mba.mbn`, `modem.mdt`, `modem.b*`)
- WiFi firmware (`wcnss.mdt`, `wcnss.b*`)
- WiFi NVRAM (`WCNSS_qcom_wlan_nv.bin`)
- Carrier config (`MCFG_SW.MBN`)

These files are placed under:

msm89xx/base-files/lib/firmware/

and are available immediately after first boot at /lib/firmware/.
Radio partitions (flashed separately)
Located in:

textstock-firmware-extract/radio/
|
├── fsc.bin
|
├── fsg.bin
|
├── modemst1.bin
|
└── modemst2.bin

These contain IMEI, calibration and EFS data and must come from your own device backup.
Custom packages

zhihe-qmi + luci-proto-zhiheqmi – cellular connection (QMI)
modem-at-engine – safe AT command interface
sms-sqlite-sync + luci-app-sms-sqlite – SMS storage & optional e-mail
luci-app-cellular-info – signal / cell info
uci-usb-gadget + luci-app-usb-gadget – USB RNDIS / gadget management


Default access after first boot


Item,Value
LAN IP,192.168.2.1
Hostname,OpenWRT-UZ801
WiFi SSID,OpenWRT-UZ801
USB RNDIS,Enabled by default
LuCI / SSH,Available on LAN (including USB Ethernet)

ItemValueLAN IP192.168.2.1HostnameOpenWRT-UZ801WiFi SSIDOpenWRT-UZ801USB RNDISEnabled by defaultLuCI / SSHAvailable on LAN (including USB Ethernet)
Even if WiFi or the cellular modem fails, you can still reach the device via USB RNDIS.

Requirements

Linux PC
edl tool
A full factory backup of your UZ801 (or at least the four radio partition files listed above)
Device in EDL mode

Entering EDL mode

From stock Android (if still working):
adb reboot edl
(enable ADB first via http://192.168.100.1/usbdebug.html)
Hardware method: short the EDL pads / D+ and GND on the USB connector while plugging in


Building
Bashgit clone https://github.com/bahbood/uz801-pureOpenwrt2.git
cd uz801-pureOpenwrt2
./build.sh
Build output will be in:
textopenwrt/bin/targets/msm89xx/msm8916/
Important artifacts:

*-squashfs-boot.img
*-squashfs-system.img
*-squashfs-gpt_both0.bin
*-firmware.zip (aboot / hyp / rpm / sbl1 / tz)
flash.sh


Flashing (empty eMMC / backup-based)

Put the device into EDL mode.
Copy the four radio files next to the build output or keep the project layout so that flash.sh can find:textstock-firmware-extract/radio/{fsc,fsg,modemst1,modemst2}.bin
From the build output directory run:Bashchmod +x flash.sh
./flash.sh

The script will:

Flash the new GPT
Flash bootloader images (aboot, hyp, rpm, sbl1, tz)
Flash OpenWrt boot + rootfs
Write the radio partitions from your local backup
Reboot the device

Do not use radio partition files from another device – this can destroy the IMEI or leave the modem permanently offline.

After first boot – cellular setup

Connect via USB RNDIS or WiFi.
Open LuCI at http://192.168.2.1.
Go to Network → Interfaces → Add new interface.
Name it modem, protocol Zhihe/Yiming QMI.
Save & Apply.

If the modem stays offline or does not attach:

Try a different MCFG_SW.MBN (region-specific files can be extracted from your original modem.bin).
Check that fsc / fsg / modemst1 / modemst2 were written correctly.


Project layout (important paths)

uz801-pureOpenwrt2/
|
├── msm89xx/
│   ├── base-files/lib/firmware/     # modem + WiFi firmware embedded in image
|   |
│   └── image/
|       |
│       ├── flash.sh                 # backup-based EDL flasher
|       |
│       ├── generate_firmware.sh     # builds aboot/hyp, downloads rpm/sbl1/tz
|       |
│       └── msm8916.mk
|
├── packages/                        # custom LuCI & modem packages
|
├── stock-firmware-extract/
|   |
│   └── radio/                       # fsc, fsg, modemst1, modemst2
|
├── build.sh
|
└── diffconfig_uz801


Notes & warnings

This image is larger than upstream builds because modem firmware is included.
msm-firmware-dumper is intentionally disabled (not present in DEVICE_PACKAGES).
Bootloader components rpm.mbn, sbl1.mbn and tz.mbn still come from the Qualcomm DragonBoard 410c reference package (via generate_firmware.sh). This is intentional for mainline compatibility.
Always keep a full edl rf backup of any working unit before experimenting.


Credits

hkfuertes/msm8916-openwrt

ImMALWARE/uz801-openwrt

AlienWolfX/UZ801-USB-MODEM

postmarketOS MSM8916 / Zhihe documentation

msm8916-mainline (lk2nd, qhypstub, qtestsign)


License
Same as upstream OpenWrt and the respective package licenses.
