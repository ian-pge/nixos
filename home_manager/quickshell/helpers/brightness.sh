# Arguments: connector, percentage-point change(s), optional previous JSON result.
# State belongs to Quickshell and is discarded whenever the monitor topology changes.
monitor="${1:?Missing monitor name}"
steps=$(jq -ce 'if type == "number" then [.] else . end
  | select(type == "array" and all(.[]; type == "number" and . == floor))' <<<"${2:-0}")
previous="${3:-null}"
changing=$(jq 'any(.[]; . != 0)' <<<"$steps")

monitors=$(hyprctl -j monitors)
target=$(jq -ce --arg name "$monitor" '.[] | select(.name == $name)' <<<"$monitors")

case "$monitor" in
  eDP-*|LVDS-*|DSI-*)
    status=$(brightnessctl --class backlight --machine-readable)
    value=$(cut -d, -f4 <<<"$status")
    value=${value%%%}
    if [[ "$changing" == true ]]; then
      next=$(jq -nr --argjson value "$value" --argjson steps "$steps" \
        'reduce $steps[] as $delta ($value; . + $delta | [0, .] | max | [100, .] | min)')
      status=$(brightnessctl --class backlight --machine-readable set "${next}%")
      value=$(cut -d, -f4 <<<"$status")
      value=${value%%%}
    fi
    jq -cn --arg monitor "$monitor" --argjson brightness "$value" \
      '{monitor: $monitor, brightness: $brightness}'
    ;;
  *)
    model=$(jq -r '.model // ""' <<<"$target")
    serial=$(jq -r '.serial // ""' <<<"$target")
    [[ -n "$model" && -n "$serial" ]] || {
      echo "Cannot identify DDC monitor $monitor uniquely" >&2
      exit 1
    }
    matches=$(jq --arg model "$model" --arg serial "$serial" \
      '[.[] | select(.model == $model and .serial == $serial)] | length' <<<"$monitors")
    [[ "$matches" == 1 ]] || { echo "Ambiguous DDC monitor identity" >&2; exit 1; }

    # Cache only a bus resolved from the connector AND monitor identity.
    # Never persist the bus across a Quickshell restart or a hotplug event.
    bus=$(jq -r --arg model "$model" --arg serial "$serial" \
      'select(.model == $model and .serial == $serial) | .bus // empty' <<<"$previous")
    if [[ ! "$bus" =~ ^[0-9]+$ ]] || [[ ! -c "/dev/i2c-$bus" ]]; then
      previous=null
      bus=$(ddcutil --brief detect | awk -v monitor="$monitor" -v model="$model" -v serial="$serial" '
        /^Display [0-9]+/ { valid=1; bus=""; connector="" }
        /^Invalid display/ { valid=0 }
        /I2C bus:/ { bus=$NF; sub("^/dev/i2c-", "", bus) }
        /DRM connector:/ { connector=$NF }
        /Monitor:/ {
          identity=$0; sub("^[[:space:]]*Monitor:[[:space:]]*[^:]*:", "", identity)
          if (valid && connector ~ ("^card[0-9]+-" monitor "$") && identity == model ":" serial)
            print bus
        }')
      [[ "$bus" =~ ^[0-9]+$ ]] || { echo "Cannot resolve DDC bus for $monitor" >&2; exit 1; }
    fi

    # Brightness (VCP 10) has the same continuous semantics in MCCS 2.1.
    # Selecting the bus and known VCP semantics avoids discovery and version queries.
    command=(ddcutil --bus "$bus" --skip-ddc-checks --mccs 2.1)
    now=$(date +%s)
    if [[ "$changing" == true ]] && jq -e --argjson now "$now" \
      'type == "object" and (.checkedAt // 0) >= ($now - 2)
        and (.checkedAt // 0) <= $now and (.maximum // 0) > 0
        and (.current | type == "number")' <<<"$previous" >/dev/null; then
      current=$(jq -r '.current' <<<"$previous")
      maximum=$(jq -r '.maximum' <<<"$previous")
    else
      status=$("${command[@]}" --brief getvcp 10)
      read -r tag code kind current maximum _ <<<"$status"
      if ! [[ "$tag $code $kind" == "VCP 10 C" && "$current" =~ ^[0-9]+$ \
        && "$maximum" =~ ^[0-9]+$ ]] || (( maximum <= 0 )); then
        echo "Cannot read brightness on $monitor: $status" >&2
        exit 1
      fi
    fi
    if [[ "$changing" == true ]]; then
      next=$(jq -nr --argjson current "$current" --argjson maximum "$maximum" \
        --argjson steps "$steps" 'reduce $steps[] as $delta ($current;
          . + ($delta * $maximum / 100 | round) | [0, .] | max | [$maximum, .] | min)')
      if (( next != current )); then
        # One verified write for the whole burst, including direction reversals.
        "${command[@]}" setvcp 10 "$next" >/dev/null
      fi
      current=$next
    fi
    value=$(((current * 100 + maximum / 2) / maximum))
    jq -cn --arg monitor "$monitor" --arg model "$model" --arg serial "$serial" \
      --argjson bus "$bus" --argjson current "$current" --argjson maximum "$maximum" \
      --argjson brightness "$value" --argjson checkedAt "$(date +%s)" \
      '{monitor: $monitor, model: $model, serial: $serial, bus: $bus,
        current: $current, maximum: $maximum, brightness: $brightness, checkedAt: $checkedAt}'
    ;;
esac
