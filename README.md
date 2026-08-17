# OpenWrt for UZ801 (backup-based / empty eMMC)

OpenWrt port for the **YiMing / FY UZ801 V3 / V3.2** USB 4G modem (Qualcomm MSM8916).

This fork is designed for devices where the **eMMC is empty, corrupted, or otherwise unusable**, and required radio/modem data must be supplied from a **local factory firmware backup** instead of being read from the live device.

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
| LTE recovery | Device dependent | Automatic QMI data-session recovery after modem/WWAN port recovery |
| LED control | Device Tree definitions | Persistent UZ801-specific runtime LED configuration |
| USB access | Device dependent | USB RNDIS/NCM gadget enabled by default |
| rootfs_data handling | Fixed flashing behavior | User-selectable keep, backup/restore, recreate, or backup-only |

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

CPU performance settings should not be changed without testing modem, WiFi, USB gadget, and overall system stability.

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

Provides USB gadget management, including USB Ethernet/RNDIS/NCM functionality.

### UZ801 LEDs

- `uz801-leds`

Provides persistent runtime control of the three main UZ801 LEDs.

### QMI recovery

- `zhihe-qmi` includes `zhihe-qmi-recovery.init`

The recovery service monitors `/dev/wwan0qmi0`. If the QMI device disappears and later reappears after a modem recovery, the service checks the QMI data-session state and can restart the `QMI` network interface when the WDS session is disconnected.

The service is installed and enabled at boot by the `zhihe-qmi` package.

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

## QMI modem recovery

The UZ801 can experience a modem-side (`remoteproc0` / MPSS) failure during some LTE link failures. In the tested configuration, the Qualcomm modem subsystem can recover without rebooting the whole OpenWrt system, but the QMI data session may remain disconnected afterward.

The project therefore includes:

```text
/etc/init.d/zhihe-qmi-recovery
```

The recovery logic is designed to:

1. Detect disappearance of `/dev/wwan0qmi0`.
2. Wait for the QMI device to reappear after modem recovery.
3. Check whether the `QMI` network interface is still up.
4. Check the QMI WDS packet-service state.
5. If WDS is disconnected, restart the `QMI` interface.
6. Allow `zhihe-qmi` to establish a new data session.

The recovery mechanism does **not** intentionally crash or reset the modem subsystem. It operates at the QMI/network-session layer and is intended to preserve the existing remoteproc recovery behavior.

The corresponding source file is:

```text
packages/zhihe-qmi/files/zhihe-qmi-recovery.init
```

---

## Default access after first boot

| Item | Value |
|---|---|
| LAN IP | `192.168.2.1` |
| Hostname | `OpenWRT-UZ801` |
| WiFi SSID | `OpenWRT-UZ801` |
| USB Ethernet/RNDIS/NCM | Enabled by default |
| LuCI / SSH | Available on LAN |
| LuCI / SSH over USB Ethernet | Available |

Even if WiFi or the cellular modem fails, USB Ethernet/gadget access provides an additional way to reach the device.

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

### Local Linux build

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

The `uz801-leds` and `zhihe-qmi` packages are included in the UZ801 device build.

### GitHub Actions

The repository includes GitHub Actions workflows:

```text
.github/workflows/build-openwrt.yml
.github/workflows/build-packages.yml
```

The firmware workflow is:

```text
Build OpenWrt for UZ801
```

It is started manually from GitHub Actions using `workflow_dispatch`.

The firmware workflow:

1. Checks out the repository.
2. Selects the latest OpenWrt `v25.12.x` tag.
3. Applies the project patches and platform files.
4. Copies the custom packages.
5. Applies `diffconfig_uz801`.
6. Downloads sources.
7. Builds OpenWrt.
8. Creates a GitHub Release containing the build artifacts.

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

The flashing script asks how `rootfs_data` should be handled before starting the destructive part of the operation.

### rootfs_data handling

The UZ801 uses:

```text
/dev/mmcblk0p15
```

as `rootfs_data` / OpenWrt overlay storage.

The flash script provides five choices:

```text
1) Keep current rootfs_data
2) Backup + Restore rootfs_data
3) Erase + Recreate rootfs_data
4) Backup rootfs_data only
5) Abort
```

#### 1) Keep current rootfs_data

The partition is left unchanged.

This preserves:

- OpenWrt configuration
- installed package state stored in overlay
- user files
- persistent settings

This is the default choice.

#### 2) Backup + Restore rootfs_data

The script first reads the complete `rootfs_data` partition into a backup image.

After the new firmware is flashed, the same backup is written back to `rootfs_data`.

A timestamped backup is created, for example:

```text
rootfs_data-backup-20260817-123456.img
```

The script verifies the backup size before continuing.

#### 3) Erase + Recreate rootfs_data

The script intentionally does **not** use:

```text
edl e rootfs_data
```

for the entire large partition.

Instead, it invalidates the existing filesystem by overwriting the beginning of the partition. On first boot, the OpenWrt preinit script:

```text
msm89xx/base-files/lib/preinit/79-format-rootfs-data
```

detects that the partition no longer has a valid ext4 filesystem and runs:

```text
mkfs.ext4 -F -L rootfs_data -O ^has_journal
```

The device then reboots into the newly created filesystem.

**All existing `rootfs_data` contents are lost in this mode.**

#### 4) Backup rootfs_data only

The script creates a complete `rootfs_data` backup and exits without flashing the device.

#### 5) Abort

No flashing operation is performed.

---

## Important rootfs_data notes

The current UZ801 GPT layout defines `rootfs_data` as the remaining space after the 128 MiB `rootfs` partition.

The current layout uses:

```text
rootfs_data start sector : 610338
rootfs_data size         : 6959037 sectors
```

The project has an explicit preinit formatter for an invalid or empty `rootfs_data` filesystem.

This design avoids depending on a full-partition Firehose erase for `rootfs_data`.

---

## Flashing sequence

The flash script performs the following major steps:

1. Detect the OpenWrt images.
2. Detect/extract bootloader firmware.
3. Locate and verify the device-specific radio backup.
4. Ask how `rootfs_data` should be handled.
5. Optionally back up `rootfs_data`.
6. Flash the new GPT.
7. Flash bootloader components.
8. Flash OpenWrt boot.
9. Flash OpenWrt rootfs.
10. Apply the selected `rootfs_data` handling mode.
11. Restore the device-specific radio partitions.
12. Reboot the device.

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

Connect to the modem through USB Ethernet/gadget or WiFi.

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

### Check the QMI session

```bash
qmicli -d /dev/wwan0qmi0 --wds-get-packet-service-status
```

A working data session should report:

```text
Connection status: 'connected'
```

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

### QMI recovery

After a modem-side recovery, check:

```bash
ls -l /dev/wwan0qmi0
```

and:

```bash
qmicli -d /dev/wwan0qmi0 --wds-get-packet-service-status
```

The automatic recovery service is:

```text
/etc/init.d/zhihe-qmi-recovery
```

---

## Project layout

```text
uz801-pureOpenwrt2/
│
├── .github/
│   └── workflows/
│       ├── build-openwrt.yml
│       └── build-packages.yml
│
├── msm89xx/
│   ├── base-files/
│   │   ├── lib/
│   │   │   ├── firmware/
│   │   │   └── preinit/
│   │   │       └── 79-format-rootfs-data
│   │
│   ├── image/
│   │   ├── flash.sh
│   │   ├── generate_firmware.sh
│   │   ├── generate_squashfs_gpt.sh
│   │   └── msm8916.mk
│   │
│   └── patches/
│       └── 803-arm64-dts-qcom-swap-leds-uz801.patch
│
├── packages/
│   ├── uz801-leds/
│   │   ├── Makefile
│   │   └── files/
│   │       └── uz801-leds.init
│   │
│   ├── zhihe-qmi/
│   │   ├── Makefile
│   │   └── files/
│   │       ├── zhiheqmi.sh
│   │       └── zhihe-qmi-recovery.init
│   │
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
├── apply_patches.sh
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

The device has shown stable operation with this configuration.

Current stability observations include:

- OpenWrt boots without the previous repeated system reboot behavior.
- USB Ethernet remains available as a recovery/access path.
- WiFi remains operational.
- LTE/QMI can recover from some modem-side failures without rebooting the whole device.
- The `zhihe-qmi` recovery service is designed to re-establish the data session after the QMI device returns.

When troubleshooting, avoid changing several components simultaneously.

---

## Notes & warnings

- This image is larger than upstream builds because modem and WiFi firmware are embedded.
- `msm-firmware-dumper` is intentionally disabled because the required firmware is supplied from the local factory backup.
- ModemManager is intentionally removed from this build.
- The cellular stack uses the custom `zhihe-qmi` implementation.
- USB Ethernet/gadget access is kept enabled as an additional recovery/access method.
- Radio/NV partitions must always come from the same physical device.
- Always keep a complete EDL backup before experimenting with partitions or firmware.
- `rootfs_data` contains persistent OpenWrt state. Use the `Keep` option during normal firmware upgrades unless a reset is intentionally required.
- The `Erase + Recreate` option destroys existing `rootfs_data` contents.
- The bootloader components `rpm.mbn`, `sbl1.mbn` and `tz.mbn` still come from the Qualcomm DragonBoard 410c reference package through `generate_firmware.sh`. This is intentional for mainline compatibility.
- The project should be treated as device-specific firmware work. Do not flash radio/NV data from another unit.

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
