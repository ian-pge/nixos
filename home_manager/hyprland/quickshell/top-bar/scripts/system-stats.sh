#!/usr/bin/env bash
set -u

read_cpu() {
  read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
  CPU_IDLE=$((idle + iowait))
  CPU_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
}

cpu=0
memory=0
disk=0
brightness=0
network_type="disconnected"
network_name="Disconnected"
network_strength=0
count=0

read_cpu
previous_idle=$CPU_IDLE
previous_total=$CPU_TOTAL

while true; do
  sleep 1

  read_cpu
  delta_idle=$((CPU_IDLE - previous_idle))
  delta_total=$((CPU_TOTAL - previous_total))
  if ((delta_total > 0)); then
    cpu=$(((100 * (delta_total - delta_idle) + delta_total / 2) / delta_total))
  fi
  previous_idle=$CPU_IDLE
  previous_total=$CPU_TOTAL

  memory=$(awk '
    /^MemTotal:/ { total = $2 }
    /^MemAvailable:/ { available = $2 }
    END { if (total > 0) printf "%.0f", 100 * (total - available) / total; else print 0 }
  ' /proc/meminfo)

  brightness=$(brightnessctl -m 2>/dev/null | awk -F, 'NR == 1 { gsub(/%/, "", $4); print $4 }')
  brightness=${brightness:-0}

  if ((count % 5 == 0)); then
    device_status=$(nmcli -t --escape no -f DEVICE,TYPE,STATE device status 2>/dev/null)
    wifi_device=$(awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }' <<< "$device_status")
    ethernet_device=$(awk -F: '$2 == "ethernet" && $3 == "connected" { print $1; exit }' <<< "$device_status")

    if [[ -n "$wifi_device" ]]; then
      network_type="wifi"
      network_name=$(nmcli -t --escape no -f IN-USE,SSID device wifi list ifname "$wifi_device" 2>/dev/null \
        | awk '$0 ~ /^\*/ { sub(/^\*:/, ""); print; exit }')
      network_name=${network_name:-$wifi_device}
      network_strength=$(nmcli -t --escape no -f IN-USE,SIGNAL device wifi list ifname "$wifi_device" 2>/dev/null \
        | awk -F: '$1 == "*" { print $2; exit }')
      network_strength=${network_strength:-0}
    elif [[ -n "$ethernet_device" ]]; then
      network_type="ethernet"
      network_name="$ethernet_device"
      network_strength=100
    elif [[ $(nmcli radio wifi 2>/dev/null) == "disabled" ]]; then
      network_type="disabled"
      network_name="Wi-Fi Off"
      network_strength=0
    else
      network_type="disconnected"
      network_name="Disconnected"
      network_strength=0
    fi
  fi

  if ((count % 30 == 0)); then
    disk=$(df -P / 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
    disk=${disk:-0}
  fi

  jq -cn \
    --argjson cpu "$cpu" \
    --argjson memory "$memory" \
    --argjson disk "$disk" \
    --argjson brightness "$brightness" \
    --arg networkType "$network_type" \
    --arg networkName "$network_name" \
    --argjson networkStrength "$network_strength" \
    '{cpu: $cpu, memory: $memory, disk: $disk, brightness: $brightness,
      networkType: $networkType, networkName: $networkName,
      networkStrength: $networkStrength}'

  count=$((count + 1))
done
