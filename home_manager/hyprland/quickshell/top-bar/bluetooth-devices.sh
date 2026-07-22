#!/usr/bin/env bash
set -u

scan=${1:-no}
if [[ "$scan" == "yes" ]]; then
  bluetoothctl --timeout 5 scan on >/dev/null 2>&1 || true
fi

paired=$(bluetoothctl devices Paired 2>/dev/null || true)
connected=$(bluetoothctl devices Connected 2>/dev/null || true)

bluetoothctl devices 2>/dev/null \
  | while IFS= read -r line; do
      [[ "$line" == Device\ * ]] || continue
      device=${line#Device }
      address=${device%% *}
      name=${device#* }
      [[ "$name" == "$address" ]] && name="Unknown device"

      is_paired=false
      is_connected=false
      if grep -Fq -- "Device $address " <<< "$paired"; then
        is_paired=true
      fi
      if grep -Fq -- "Device $address " <<< "$connected"; then
        is_connected=true
      fi

      jq -cn \
        --arg address "$address" \
        --arg name "$name" \
        --argjson paired "$is_paired" \
        --argjson connected "$is_connected" \
        '{address: $address, name: $name, paired: $paired, connected: $connected}'
    done \
  | jq -sc 'sort_by(if .connected then 0 elif .paired then 1 else 2 end, .name)'
