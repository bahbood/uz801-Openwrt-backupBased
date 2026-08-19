#!/bin/sh
#
# Zhihe/YiMing QMI protocol handler for OpenWrt netifd.
#
# Features:
#   - Stable profile-based WDS startup.
#   - IPv4 support.
#   - IPv6 support.
#   - Safe WDS PID handling.
#   - IPv6 offlink address handling for point-to-point wwan0.
#   - IPv6 gateway host route before default route.
#
# Important:
#   Do not poll WDS status while --wds-follow-network is running.
#   This caused endpoint hangup / transaction timeout on UZ801.
#

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
	local pidfile="/var/run/zhiheqmi_${config}.pid"
	local pid

	pid=$(cat "$pidfile" 2>/dev/null)

	if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then

		if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null |
			grep -q "qmicli"; then

			kill -TERM "$pid" 2>/dev/null
			sleep 1

			[ -d "/proc/$pid" ] &&
				kill -KILL "$pid" 2>/dev/null
		fi
	fi

	rm -f "$pidfile"
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

	local ip6
	local ip6_prefix
	local gw6
	local dns6_1
	local dns6_2

	#
	# IPv4
	#

	ip=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*IPv4 address:[[:space:]]*\([^[:space:]]*\).*/\1/p' |
		head -n 1
	)

	gw=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*IPv4 gateway address:[[:space:]]*\([^[:space:]]*\).*/\1/p' |
		head -n 1
	)

	mask=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*IPv4 subnet mask:[[:space:]]*\([^[:space:]]*\).*/\1/p' |
		head -n 1
	)

	dns1=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*IPv4 primary DNS:[[:space:]]*\([^[:space:]]*\).*/\1/p' |
		head -n 1
	)

	dns2=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*IPv4 secondary DNS:[[:space:]]*\([^[:space:]]*\).*/\1/p' |
		head -n 1
	)

	mtu=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*MTU:[[:space:]]*\([0-9][0-9]*\).*/\1/p' |
		head -n 1
	)

	#
	# IPv6
	#

	ip6=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*IPv6 address:[[:space:]]*\([^[:space:]]*\).*/\1/p' |
		head -n 1
	)

	if [ -n "$ip6" ]; then

		ip6_prefix="${ip6##*/}"

		case "$ip6_prefix" in
			''|*[!0-9]*)
				ip6_prefix=""
				;;
		esac

		if [ -n "$ip6_prefix" ]; then
			ip6="${ip6%/*}"
		fi
	fi

	gw6=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*IPv6 gateway address:[[:space:]]*\([^[:space:]]*\).*/\1/p' |
		head -n 1
	)

	case "$gw6" in
		*/*)
			gw6="${gw6%%/*}"
			;;
	esac

	dns6_1=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*IPv6 primary DNS:[[:space:]]*\([^[:space:]]*\).*/\1/p' |
		head -n 1
	)

	dns6_2=$(
		echo "$settings" |
		sed -n 's/^[[:space:]]*IPv6 secondary DNS:[[:space:]]*\([^[:space:]]*\).*/\1/p' |
		head -n 1
	)

	#
	# IPv4 CIDR
	#

	if [ -n "$mask" ]; then
		cidr=$(mask_to_cidr "$mask")
	fi

	#
	# At least one family must exist.
	#

	if [ -z "$ip" ] && [ -z "$ip6" ]; then
		return 1
	fi

	#
	# Logging
	#

	if [ -n "$ip" ]; then
		logger -t zhihe-qmi \
			"IPv4: $ip/$cidr, GW: $gw, DNS: $dns1, $dns2"
	fi

	if [ -n "$ip6" ]; then
		logger -t zhihe-qmi \
			"IPv6: $ip6/$ip6_prefix, GW: $gw6, DNS: $dns6_1, $dns6_2"
	fi

	#
	# Start netifd update.
	#

	proto_init_update "$iface" 1

	#
	# IPv4
	#

	if [ -n "$ip" ] && [ -n "$cidr" ]; then

		proto_add_ipv4_address \
			"$ip" \
			"$cidr" \
			"" \
			"$gw"

		if [ -n "$gw" ]; then
			proto_add_ipv4_route \
				"0.0.0.0" \
				0 \
				"$gw"
		else
			proto_add_ipv4_route \
				"0.0.0.0" \
				0
		fi
	fi

	#
	# IPv6
	#
	# The UZ801 wwan0 interface is point-to-point.
	#
	# offlink=1 is important here. Our direct test proved that
	# netifd can install the global IPv6 address on wwan0 with it.
	#

	if [ -n "$ip6" ] && [ -n "$ip6_prefix" ]; then

		proto_add_ipv6_address \
			"$ip6" \
			"$ip6_prefix" \
			"" \
			"" \
			1

		#
		# The QMI IPv6 gateway is a global address.
		# Add it as a /128 route first so Linux can resolve
		# the next-hop before installing the default route.
		#

		if [ -n "$gw6" ]; then

			proto_add_ipv6_route \
				"$gw6" \
				128

			proto_add_ipv6_route \
				"::" \
				0 \
				"$gw6"

		else

			#
			# Fallback for sessions without an explicit gateway.
			#

			proto_add_ipv6_route \
				"::" \
				0
		fi
	fi

	#
	# IPv4 DNS
	#

	if [ -n "$dns1" ]; then
		proto_add_dns_server "$dns1"
	fi

	if [ -n "$dns2" ]; then
		proto_add_dns_server "$dns2"
	fi

	#
	# IPv6 DNS
	#

	if [ -n "$dns6_1" ]; then
		proto_add_dns_server "$dns6_1"
	fi

	if [ -n "$dns6_2" ]; then
		proto_add_dns_server "$dns6_2"
	fi

	#
	# MTU
	#

	if [ -n "$mtu" ]; then
		json_add_int mtu "$mtu"
	fi

	#
	# Send IPv4 + IPv6 together in ONE update.
	#

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
	local settings
	local ip_ready

	json_get_vars device apn profile

	[ -z "$device" ] && device="/dev/wwan0qmi0"
	[ -z "$apn" ] && apn="internet"
	[ -z "$profile" ] && profile="3"
	[ -z "$iface" ] && iface="wwan0"

	logger -t zhihe-qmi \
		"Starting connection on $iface ($device) with APN: $apn, Profile: $profile"

	#
	# Wait for QMI device.
	#

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

	#
	# Bring interface up.
	#

	ip link set "$iface" up 2>/dev/null || true

	#
	# Put modem online.
	#

	qmicli \
		-d "$device" \
		--device-open-proxy \
		--dms-set-operating-mode=online \
		>/dev/null 2>&1

	logger -t zhihe-qmi \
		"Waiting for network registration..."

	#
	# Wait for network registration.
	#

	registered=0
	elapsed=0

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

	logger -t zhihe-qmi \
		"Registered to network."

	#
	# Keep the original UZ801 WDS startup behavior.
	#
	# Do NOT poll --wds-get-packet-service-status while the
	# qmicli --wds-follow-network process is running.
	#

	qmicli \
		-d "$device" \
		--device-open-net='net-raw-ip|net-no-qos-header' \
		--wds-start-network="3gpp-profile=$profile" \
		--device-open-proxy \
		--wds-follow-network \
		>/dev/null 2>&1 &

	echo "$!" > "/var/run/zhiheqmi_${config}.pid"

	logger -t zhihe-qmi \
		"WDS start requested for profile $profile"

	#
	# Wait for IPv4 or IPv6 settings.
	#

	ip_ready=0
	elapsed=0

	while [ "$elapsed" -lt 60 ]; do

		settings=$(proto_zhiheqmi_get_settings "$device")

		if [ -n "$settings" ]; then

			if echo "$settings" |
				grep -qE "IPv4 address:|IPv6 address:"; then

				ip_ready=1
				break
			fi
		fi

		sleep 2
		elapsed=$((elapsed + 2))
	done

	if [ "$ip_ready" -eq 0 ]; then

		logger -t zhihe-qmi \
			"IP settings not available after 60 seconds"

		proto_zhiheqmi_kill_wds "$config"

		proto_notify_error "$config" "IP_FETCH_FAILED"

		sleep 20
		proto_setup_failed "$config"

		return 1
	fi

	#
	# Read final settings once more.
	#

	settings=$(proto_zhiheqmi_get_settings "$device")

	if [ -z "$settings" ]; then

		logger -t zhihe-qmi \
			"Current settings unavailable after WDS start"

		proto_zhiheqmi_kill_wds "$config"

		proto_notify_error "$config" "IP_FETCH_FAILED"

		sleep 20
		proto_setup_failed "$config"

		return 1
	fi

	#
	# Apply IPv4/IPv6 to netifd.
	#

	if ! proto_zhiheqmi_apply_settings \
		"$config" \
		"$iface" \
		"$settings"; then

		logger -t zhihe-qmi \
			"Failed to apply IP settings"

		proto_zhiheqmi_kill_wds "$config"

		proto_notify_error "$config" "IP_FETCH_FAILED"

		sleep 20
		proto_setup_failed "$config"

		return 1
	fi

	logger -t zhihe-qmi \
		"QMI network setup complete"
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