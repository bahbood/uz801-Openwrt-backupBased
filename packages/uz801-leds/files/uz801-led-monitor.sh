#!/bin/sh

LED="/sys/class/leds/green:wan/brightness"
DEVICE="/dev/wwan0qmi0"
INTERFACE="QMI"
NETDEV="wwan0"

set_led() {
	[ -w "$LED" ] || return 0
	echo "$1" > "$LED"
}

has_ipv4() {
	ip -4 -o addr show dev "$NETDEV" scope global 2>/dev/null |
		grep -q 'inet '
}

qmi_connected() {
	[ -c "$DEVICE" ] || return 1

	qmicli \
		-d "$DEVICE" \
		--device-open-proxy \
		--wds-get-packet-service-status \
		2>/dev/null |
		grep -q "Connection status: 'connected'"
}

qmi_interface_up() {
	ubus call network.interface "$INTERFACE" status 2>/dev/null |
		grep -q '"up": true'
}

set_led 0

while true; do
	if qmi_interface_up &&
	   qmi_connected &&
	   has_ipv4; then
		set_led 1
	else
		set_led 0
	fi

	sleep 3
done