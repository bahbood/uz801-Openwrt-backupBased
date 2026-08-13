#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_zhiheqmi_init_config() {
	available=1
	no_device=1

	proto_config_add_string "device:device"
	proto_config_add_string "apn"
	proto_config_add_string "profile"
}

proto_zhiheqmi_kill_wds() {
	local config="$1"
	local pid

	pid=$(cat "/var/run/zhiheqmi_${config}.pid" 2>/dev/null)

	if [ -n "$pid" ]; then
		kill -TERM "$pid" 2>/dev/null
		sleep 1
		kill -KILL "$pid" 2>/dev/null
	fi

	rm -f "/var/run/zhiheqmi_${config}.pid"
}

mask_to_cidr() {
	local mask="$1"

	case "$mask" in
		255.255.255.255) echo 32 ;;
		255.255.255.254) echo 31 ;;
		255.255.255.252) echo 30 ;;
		255.255.255.248) echo 29 ;;
		255.255.255.240) echo 28 ;;
		255.255.255.224) echo 27 ;;
		255.255.255.192) echo 26 ;;
		255.255.255.128) echo 25 ;;
		255.255.255.0)   echo 24 ;;
		255.255.254.0)   echo 23 ;;
		255.255.252.0)   echo 22 ;;
		255.255.248.0)   echo 21 ;;
		255.255.240.0)   echo 20 ;;
		255.255.224.0)   echo 19 ;;
		255.255.192.0)   echo 18 ;;
		255.255.128.0)   echo 17 ;;
		255.255.0.0)     echo 16 ;;
		255.254.0.0)     echo 15 ;;
		255.252.0.0)     echo 14 ;;
		255.248.0.0)     echo 13 ;;
		255.240.0.0)     echo 12 ;;
		255.224.0.0)     echo 11 ;;
		255.192.0.0)     echo 10 ;;
		255.128.0.0)     echo 9 ;;
		255.0.0.0)       echo 8 ;;
		0.0.0.0)         echo 0 ;;
		*)               echo 32 ;;
	esac
}

proto_zhiheqmi_get_settings() {
	local device="$1"

	qmicli \
		-d "$device" \
		--device-open-proxy \
		--wds-get-current-settings \
		2>/dev/null
}

proto_zhiheqmi_apply_settings() {
	local config="$1"
	local iface="$2"
	local settings="$3"

	local ip
	local gw
	local mask
	local dns1
	local dns2
	local mtu
	local cidr

	ip=$(echo "$settings" |
		grep -oE "IPv4 address: [0-9.]+" |
		awk '{print $3}')

	gw=$(echo "$settings" |
		grep -oE "IPv4 gateway address: [0-9.]+" |
		awk '{print $4}')

	mask=$(echo "$settings" |
		grep -oE "IPv4 subnet mask: [0-9.]+" |
		awk '{print $4}')

	dns1=$(echo "$settings" |
		grep -oE "IPv4 primary DNS: [0-9.]+" |
		awk '{print $4}')

	dns2=$(echo "$settings" |
		grep -oE "IPv4 secondary DNS: [0-9.]+" |
		awk '{print $4}')

	mtu=$(echo "$settings" |
		grep -oE "MTU: [0-9]+" |
		awk '{print $2}')

	if [ -z "$ip" ] || [ -z "$mask" ]; then
		return 1
	fi

	cidr=$(mask_to_cidr "$mask")

	logger -t zhihe-qmi \
		"Success! IP: $ip/$cidr, GW: $gw, MTU: $mtu, DNS: $dns1, $dns2"

	proto_init_update "$iface" 1
	proto_add_ipv4_address "$ip" "$cidr" "" "$gw"

	if [ -n "$gw" ]; then
		proto_add_ipv4_route "0.0.0.0" 0 "$gw"
	fi

	if [ -n "$dns1" ]; then
		proto_add_dns_server "$dns1"
	fi

	if [ -n "$dns2" ]; then
		proto_add_dns_server "$dns2"
	fi

	if [ -n "$mtu" ]; then
		json_add_int mtu "$mtu"
	fi

	proto_send_update "$config"
	return 0
}

proto_zhiheqmi_setup() {
	local config="$1"
	local iface="$2"
	local device
	local apn
	local profile
	local elapsed
	local status
	local registered
	local wds_status
	local settings
	local ip_ready

	json_get_vars device apn profile

	[ -z "$device" ] && device="/dev/wwan0qmi0"
	[ -z "$apn" ] && apn="internet"
	[ -z "$profile" ] && profile="3"
	[ -z "$iface" ] && iface="wwan0"

	logger -t zhihe-qmi \
		"Starting connection on $iface ($device) with APN: $apn, Profile: $profile"

	# Wait for remoteproc/QMI device.
	elapsed=0

	while [ "$elapsed" -lt 60 ]; do
		if [ -c "$device" ]; then
			break
		fi

		sleep 2
		elapsed=$((elapsed + 2))
	done

	if [ ! -c "$device" ]; then
		logger -t zhihe-qmi \
			"QMI device unavailable after 60 seconds: $device"

		proto_notify_error "$config" "NO_DEVICE"
		sleep 10
		proto_setup_failed "$config"
		return 1
	fi

	ip link set "$iface" up 2>/dev/null || true

	# Put modem online. Do not reset WDS here.
	qmicli \
		-d "$device" \
		--device-open-proxy \
		--dms-set-operating-mode=online \
		>/dev/null 2>&1

	logger -t zhihe-qmi \
		"Waiting for network registration..."

	registered=0
	elapsed=0

	# Wait up to 180 seconds.
	while [ "$elapsed" -lt 180 ]; do
		status=$(
			qmicli \
				-d "$device" \
				--device-open-proxy \
				--nas-get-serving-system \
				2>/dev/null
		)

		if echo "$status" |
			grep -q "Registration state: 'registered'"; then
			registered=1
			break
		fi

		sleep 2
		elapsed=$((elapsed + 2))
	done

	if [ "$registered" -eq 0 ]; then
		logger -t zhihe-qmi \
			"Network registration timeout after 180 seconds"

		proto_notify_error "$config" "REGISTRATION_FAILED"
		sleep 20
		proto_setup_failed "$config"
		return 1
	fi

	logger -t zhihe-qmi "Registered to network."

	# IMPORTANT:
	# Never start another WDS session if one is already connected.
	wds_status=$(
		qmicli \
			-d "$device" \
			--device-open-proxy \
			--wds-get-packet-service-status \
			2>/dev/null
	)

	if echo "$wds_status" |
		grep -q "Connection status: 'connected'"; then

		logger -t zhihe-qmi \
			"WDS already connected; reusing existing data session"

	else
		logger -t zhihe-qmi \
			"WDS disconnected; starting profile $profile"

		qmicli \
			-d "$device" \
			--device-open-net='net-raw-ip|net-no-qos-header' \
			--wds-start-network="3gpp-profile=$profile" \
			--device-open-proxy \
			--wds-follow-network \
			>/dev/null 2>&1 &

		echo "$!" > "/var/run/zhiheqmi_${config}.pid"
	fi

	# Wait for IPv4 settings.
	ip_ready=0
	elapsed=0

	while [ "$elapsed" -lt 60 ]; do
		settings=$(proto_zhiheqmi_get_settings "$device")

		if [ -n "$settings" ]; then
			if echo "$settings" |
				grep -q "IPv4 address:"; then
				ip_ready=1
				break
			fi
		fi

		sleep 2
		elapsed=$((elapsed + 2))
	done

	if [ "$ip_ready" -eq 0 ]; then
		logger -t zhihe-qmi \
			"IPv4 settings not available after 60 seconds"

		proto_zhiheqmi_kill_wds "$config"

		proto_notify_error "$config" "IP_FETCH_FAILED"
		sleep 20
		proto_setup_failed "$config"
		return 1
	fi

	# Apply the final modem settings to netifd.
	settings=$(proto_zhiheqmi_get_settings "$device")

	if ! proto_zhiheqmi_apply_settings \
		"$config" "$iface" "$settings"; then

		logger -t zhihe-qmi \
			"Failed to apply IPv4 settings"

		proto_zhiheqmi_kill_wds "$config"

		proto_notify_error "$config" "IP_FETCH_FAILED"
		sleep 20
		proto_setup_failed "$config"
		return 1
	fi
}

proto_zhiheqmi_teardown() {
	local config="$1"
	local iface="$2"

	[ -z "$iface" ] && iface="wwan0"

	logger -t zhihe-qmi \
		"Tearing down connection on $iface..."

	proto_zhiheqmi_kill_wds "$config"

	ip link set "$iface" down 2>/dev/null || true
}

[ -n "$INCLUDE_ONLY" ] || add_protocol zhiheqmi

