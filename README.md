# OpenWrt for UZ801 modem

# Changes in this fork

ModemManager crashed the modem on this device, so custom packages were written to manage cellular connection and SMS, along with corresponding LuCI apps. Scripts are based on postmarketOS wiki advice.

Citation from postmarketOS wiki:

> On my UZ801 V3.2, the process of getting a fresh pmOS image to connect to LTE was rather painful. The internet lists some misleading instructions (qmi-network script does not work out of the box here), and in other cases suggests setting sysctl keys which do not exist. This device also does not work with ModemManager, nor ofono, straight up crashing the latter. Hence, all of this has been determined through manual trial and error.

`alias q='qmicli -d /dev/wwan0qmi0'`

> Device-specific quirks:
> - Setting the data format through `q --wda-set-data-format=raw-ip` does not seem to work. It falsely returns success, but `--wda-set-data-format` says 802-3 still. Instead, append `--device-open-net='net-raw-ip|net-no-qos-header'` to the `wds-start-network` call
> - `--client-cid=...` is evil and will hang `qmicli`. Of note, it doesn't hang the modem, just causes it to never respond, and `qmicli` is bad at handling timeouts
> - `--wds-go-dormant` / `--wds-go-active` doesn't do anything. Generally my version seems to be quite cut down, even `--wds-get-supported-messages` fails
> - `--client-no-release-cid` fails, use `--wds-follow-network` instead. This will lock up your shell, however. To disconnect, first ^C so `qmicli` sends a disconnection request to the modem, then ^Z, then `killall -9 qmicli` (otherwise it'll hang forever)
> - `qmicli` seems to be randomly unable to receive status back from the modem. This will result in "error: operation failed: Transaction timed out". This Is Fine™

sms-tool and [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) also crashed the modem.

## Removed

- WireGuard
- ModemManager
- AmneziaWG

## Added / Improved

- Russian language
- NFQUEUE + PBR
- mailsend
- sing-box
- SMB server (ksmbd)
- Kernel patch for counting RX/TX packets and bytes
- USB Gadget (RNDIS) always enabled for reliable management access
- Default LAN IP: `192.168.2.1`
- Hostname: `OpenWRT-UZ801`
- WiFi SSID: `OpenWRT-UZ801`
- Firewall lan zone kept open (input/output/forward ACCEPT) for USB management
- DHCP range tuned (start 100, limit 150, leasetime 5d)
- tsens EPROBE_DEFER propagation patch

## Packages written from scratch

- **zhihe-qmi** + **luci-proto-zhiheqmi** – cellular connection. Add `modem` interface with protocol `Zhihe/Yiming QMI`.
- **modem-at-engine** – ubus service to send AT commands without crashing the modem.
- **sms-sqlite-sync** + **luci-app-sms-sqlite** – checks for new SMS every 3 minutes, stores them in SQLite, optional email notification. LuCI app for viewing/sending SMS.
- **luci-app-cellular-info** – cellular connection info, signal strength, nearby cells.
- **uci-usb-gadget** + **luci-app-usb-gadget** – USB Gadget management (RNDIS for Ethernet-over-USB).

Unfortunately, IPv6 on the cellular connection could not be set up yet.

---

# Default access after first boot

| Item              | Value              |
|-------------------|--------------------|
| LAN IP            | `192.168.2.1`      |
| Hostname          | `OpenWRT-UZ801`    |
| WiFi SSID         | `OpenWRT-UZ801`    |
| USB RNDIS         | Enabled by default |
| LuCI / SSH        | Available on LAN (including USB Ethernet) |

Even if WiFi hangs or the SIM/modem has problems, you can still reach the device via USB Ethernet (RNDIS).

---

# How to install from Linux computer

1. Download all files from the latest OpenWrt release [](https://github.com/ImMALWARE/uz801-openwrt/releases).
2. Enable ADB on the modem by opening http://192.168.100.1/usbdebug.html
3. Install `adb` and [edl tools](https://github.com/bkerler/edl) on your computer.
4. When connected to the modem via USB, run `adb reboot edl` to reboot into EDL mode.
5. Make a full backup of the original firmware:
   ```sh
   edl rf stock.bin
   edl rl stock --genxml
