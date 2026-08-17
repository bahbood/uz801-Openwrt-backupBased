#!/bin/sh

LED="/sys/class/leds/green:wan"
BRIGHTNESS="$LED/brightness"
TRIGGER="$LED/trigger"

DEVICE="/dev/wwan0qmi0"
INTERFACE="QMI"
NETDEV="wwan0"

set_led() {
	local state="$1"

	[ -w "$BRIGHTNESS" ] || return 0

	if [ "$state" = "1" ]; then
		[ "$(cat "$BRIGHTNESS" 2>/dev/null)" = "1" ] || echo 1 > "$BRIGHTNESS"
	else
		[ "$(cat "$BRIGHTNESS" 2>/dev/null)" = "0" ] || echo 0 > "$BRIGHTNESS"
	fi
}

has_ipv4() {
	ip -4 -o addr show dev "$NETDEV" scope global 2>/dev/null |
		grep -q ' inet '
}

qmi_interface_up() {
	ubus call "network.interface.${INTERFACE}" status 2>/dev/null |
		grep -q '"up": true'
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

# Green LED must be under manual control.
echo none > "$TRIGGER" 2>/dev/null || true

# Start with LED off.
set_led 0

last_state="-1"

while true; do
	state=0

	if qmi_interface_up &&
		qmi_connected &&
		has_ipv4; then
		state=1
	fi

	# Only touch the LED when its state actually changes.
	if [ "$state" != "$last_state" ]; then
		set_led "$state"
		last_state="$state"
	fi

	sleep 3
done
