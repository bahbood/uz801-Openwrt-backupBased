# OpenWrt for UZ801 (backup-based / empty eMMC)

OpenWrt port for the **YiMing / FY UZ801 V3 / V3.2** USB 4G modem (Qualcomm MSM8916).

This fork is designed for the case where the device **eMMC is empty, corrupted, or not usable**, and all required radio/modem data must come from a **local factory firmware backup** instead of being read from the live device.

Based on the work of:

- https://github.com/hkfuertes/msm8916-openwrt
- https://github.com/ImMALWARE/uz801-openwrt

---

## Main differences of this fork

| Feature | Upstream | This fork |
|---|---|---|
| Modem firmware source | Dumped from device on first boot (`msm-firmware-dumper`) | Embedded in the image from a local backup |
| Radio / NV partitions (`fsc`, `fsg`, `modemst1`, `modemst2`) | Backed up from live device during flash | Taken from `stock-firmware-extract/radio/` |
| Assumption about eMMC | Stock or previously working firmware present | eMMC may be empty / unusable |
| ModemManager | Removed | Removed |
| Cellular stack | Standard modem handling | Custom `zhihe-qmi` + LuCI apps |
| LED control | Device Tree definitions | Persistent UZ801-specific runtime LED configuration |
| USB access | Device dependent | USB RNDIS enabled by default |

---

## Hardware

- **Device:** YiMing / FY UZ801 V3 / V3.2
- **SoC:** Qualcomm MSM8916
- **Storage:** eMMC
- **Cellular modem:** Qualcomm MSM8916 modem subsystem
- **WiFi:** Qualcomm WCNSS / WCN36xx
- **Boot protocol:** Qualcomm Sahara / Firehose / EDL

---

## CPU configuration

The current tested configuration uses:

- **2 CPU cores**
- **Maximum CPU frequency: 800 MHz**

This configuration has been tested on the UZ801 and is currently preferred for stability.

CPU performance settings should not be changed without testing modem, WiFi and system stability.

---

## Firmware embedded in the image

The following modem and WiFi firmware files are embedded directly into the OpenWrt image:

- `mba.mbn`
- `modem.mdt`
- `modem.b*`
- `wcnss.mdt`
- `wcnss.b*`
- `WCNSS_qcom_wlan_nv.bin`
- `MCFG_SW.MBN`

They are placed under:

```text
msm89xx/base-files/lib/firmware/
```

and are available after first boot under:

```text
/lib/firmware/
```

This eliminates the need for `msm-firmware-dumper` on first boot.

---

## Radio / NV partitions

The following partitions are flashed separately from the local factory backup:

```text
stock-firmware-extract/radio/

├── fsc.bin
├── fsg.bin
├── modemst1.bin
└── modemst2.bin
```

These partitions contain device-specific radio data such as:

- IMEI
- calibration data
- EFS/NV data
- modem configuration data

**These files must come from the same physical device.**

Do not use radio/NV partitions from another UZ801.

Using another device's `fsc`, `fsg`, `modemst1` or `modemst2` can destroy the device's IMEI configuration or leave the modem permanently offline.

---

## Custom packages

### Cellular

- `zhihe-qmi`
- `luci-proto-zhiheqmi`

Used for the custom Qualcomm/Zhihe QMI cellular connection.

### AT command interface

- `modem-at-engine`

Provides a controlled AT command interface without relying on ModemManager.

### SMS

- `sms-sqlite-sync`
- `luci-app-sms-sqlite`

Provides SMS storage and optional e-mail synchronization.

### Cellular information

- `luci-app-cellular-info`

Provides cellular signal and serving-cell information.

### USB gadget

- `uci-usb-gadget`
- `luci-app-usb-gadget`

Provides USB gadget management including USB Ethernet/RNDIS functionality.

### UZ801 LEDs

- `uz801-leds`

Provides persistent runtime control of the three main UZ801 LEDs.

---

## UZ801 LED configuration

The UZ801 hardware exposes three main status LEDs:

| LED | Linux name | Function |
|---|---|---|
| Red | `red:power` | Power |
| Green | `green:wan` | LTE/WAN |
| Blue | `blue:wlan` | WiFi |

The Device Tree assigns the WLAN and WAN functions:

```text
blue  → LED_FUNCTION_WLAN
green → LED_FUNCTION_WAN
red   → Power
```

The project additionally includes the `uz801-leds` package, which configures the LEDs at runtime.

### Current behavior

**Red Power LED**

```text
red:power
trigger: none
brightness: 1
```

The red LED remains continuously on while the device is running.

**Green LTE/WAN LED**

```text
green:wan
trigger: netdev
device: wwan0
link: 1
rx: 0
tx: 0
```

The green LED follows the link state of the LTE interface `wwan0`.

**Blue WiFi LED**

```text
blue:wlan
trigger: netdev
device: phy0-ap0
link: 1
rx: 0
tx: 0
```

The blue LED follows the link state of the WiFi AP interface `phy0-ap0`.

The LED configuration is applied automatically during boot by:

```text
/etc/init.d/uz801-leds
```

The corresponding source package is:

```text
packages/uz801-leds/
```

The package is included specifically in the UZ801 device profile through:

```text
msm89xx/image/msm8916.mk
```

No manual LED configuration is required after installation.

---

## Default access after first boot

| Item | Value |
|---|---|
| LAN IP | `192.168.2.1` |
| Hostname | `OpenWRT-UZ801` |
| WiFi SSID | `OpenWRT-UZ801` |
| USB RNDIS | Enabled by default |
| LuCI / SSH | Available on LAN |
| LuCI / SSH over USB Ethernet | Available |

Even if WiFi or the cellular modem fails, USB Ethernet/RNDIS provides an additional way to reach the device.

LuCI:

```text
http://192.168.2.1
```

---

## Requirements

A Linux PC is recommended.

Required:

- Linux PC
- `edl` / Qualcomm Firehose tool
- Full factory backup of the UZ801
- Radio partition backup:
  - `fsc.bin`
  - `fsg.bin`
  - `modemst1.bin`
  - `modemst2.bin`
- Device in Qualcomm EDL mode

---

## Entering EDL mode

### From stock Android

If the original firmware is still operational:

```bash
adb reboot edl
```

ADB may need to be enabled first through:

```text
http://192.168.100.1/usbdebug.html
```

### Hardware method

The device can also be placed into EDL mode using the appropriate hardware EDL pads / USB test points.

---

## Building

Clone the repository:

```bash
git clone https://github.com/bahbood/uz801-pureOpenwrt2.git
cd uz801-pureOpenwrt2
```

Run:

```bash
./build.sh
```

Build output:

```text
openwrt/bin/targets/msm89xx/msm8916/
```

Important artifacts include:

```text
*-squashfs-boot.img
*-squashfs-system.img
*-squashfs-gpt_both0.bin
*-firmware.zip
flash.sh
```

The `uz801-leds` package is automatically included in the `yiming-uz801v3` device profile.

---

## Flashing (empty eMMC / backup-based)

Put the device into EDL mode.

Make sure the device-specific radio files are available:

```text
stock-firmware-extract/radio/
├── fsc.bin
├── fsg.bin
├── modemst1.bin
└── modemst2.bin
```

From the build output directory:

```bash
chmod +x flash.sh
./flash.sh
```

The flashing process will:

1. Flash the new GPT.
2. Flash bootloader images.
3. Flash the OpenWrt boot image.
4. Flash the OpenWrt root filesystem.
5. Write the device-specific radio partitions.
6. Reboot the device.

### Warning

**Never use radio partition files from another UZ801.**

The following files are device-specific:

```text
fsc.bin
fsg.bin
modemst1.bin
modemst2.bin
```

Always keep a complete EDL backup of the original device.

---

## After first boot – cellular setup

Connect to the modem through USB RNDIS or WiFi.

Open LuCI:

```text
http://192.168.2.1
```

Go to:

```text
Network → Interfaces → Add new interface
```

Create the cellular interface using:

```text
Protocol: Zhihe/Yiming QMI
```

Save and apply the configuration.

The cellular interface is normally exposed as:

```text
wwan0
```

and the QMI device is typically:

```text
/dev/wwan0qmi0
```

---

## If the modem stays offline

### MCFG

Try another region-specific `MCFG_SW.MBN`.

Region-specific MCFG files can be extracted from the original `modem.bin`.

### Radio partitions

Verify that the following files were taken from the same device and written correctly:

```text
fsc.bin
fsg.bin
modemst1.bin
modemst2.bin
```

### Firmware

Verify that the modem firmware is present:

```bash
ls -l /lib/firmware/
```

Important files include:

```text
mba.mbn
modem.mdt
wcnss.mdt
WCNSS_qcom_wlan_nv.bin
MCFG_SW.MBN
```

---

## Project layout

```text
uz801-pureOpenwrt2/
│
├── msm89xx/
│   ├── base-files/
│   │   └── lib/
│   │       └── firmware/
│   │           # Embedded modem + WiFi firmware
│   │
│   ├── image/
│   │   └── msm8916.mk
│   │       # UZ801 device profile and DEVICE_PACKAGES
│   │
│   └── patches/
│       └── 803-arm64-dts-qcom-swap-leds-uz801.patch
│           # UZ801 LED Device Tree definitions
│
├── packages/
│   ├── uz801-leds/
│   │   ├── Makefile
│   │   └── files/
│   │       └── uz801-leds.init
│   │
│   ├── zhihe-qmi/
│   ├── luci-proto-zhiheqmi/
│   ├── modem-at-engine/
│   ├── sms-sqlite-sync/
│   ├── luci-app-sms-sqlite/
│   ├── luci-app-cellular-info/
│   └── uci-usb-gadget/
│
├── stock-firmware-extract/
│   └── radio/
│       ├── fsc.bin
│       ├── fsg.bin
│       ├── modemst1.bin
│       └── modemst2.bin
│
├── build.sh
└── diffconfig_uz801
```

---

## Stability notes

The current UZ801 configuration has been tested with:

```text
CPU cores:       2
Maximum CPU:     800 MHz
```

This configuration is currently preferred because the modem has demonstrated stable operation under this setting.

The following components should be considered together when evaluating stability:

- Qualcomm modem subsystem
- `zhihe-qmi`
- WiFi / WCNSS
- USB gadget
- CPU frequency configuration
- eMMC / overlay filesystem

Avoid changing several of these components simultaneously when troubleshooting stability.

---

## Notes & warnings

- This image is larger than upstream builds because modem and WiFi firmware are embedded.
- `msm-firmware-dumper` is intentionally disabled because the required firmware is supplied from the local factory backup.
- ModemManager is intentionally removed from this build.
- The cellular stack uses the custom `zhihe-qmi` implementation.
- USB RNDIS is kept enabled as an additional recovery/access method.
- Radio/NV partitions must always come from the same physical device.
- Always keep a complete EDL backup before experimenting with partitions or firmware.
- Bootloader components `rpm.mbn`, `sbl1.mbn` and `tz.mbn` still come from the Qualcomm DragonBoard 410c reference package through `generate_firmware.sh`. This is intentional for mainline compatibility.

---

## Credits

- https://github.com/hkfuertes/msm8916-openwrt
- https://github.com/ImMALWARE/uz801-openwrt
- AlienWolfX / UZ801-USB-MODEM
- postmarketOS MSM8916 / Zhihe documentation
- msm8916-mainline
- lk2nd
- qhypstub
- qtestsign

---

## License

Same as upstream OpenWrt and the respective package licenses.
