#!/usr/bin/env bash
set -u

rescan=${1:-auto}
if [[ "$rescan" != "yes" && "$rescan" != "auto" ]]; then
  rescan=auto
fi

known_wifi=$(nmcli -t --escape no -f NAME,TYPE connection show 2>/dev/null \
  | awk -F: '
      $NF == "802-11-wireless" {
        name = $1
        for (i = 2; i < NF; i++) name = name ":" $i
        print name
      }
    ')

nmcli -t --escape no -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan "$rescan" 2>/dev/null \
  | awk -F: '
      {
        ssid = $4
        for (i = 5; i <= NF; i++) ssid = ssid ":" $i
        if (ssid == "") next

        signal = $2 + 0
        is_active = ($1 == "*")
        if (!(ssid in strongest) || signal > strongest[ssid]) {
          strongest[ssid] = signal
          security[ssid] = $3
        }
        if (is_active) active[ssid] = 1
      }
      END {
        for (ssid in strongest)
          printf "%s\t%d\t%s\t%d\n", ssid, strongest[ssid], security[ssid], active[ssid] ? 1 : 0
      }
    ' \
  | while IFS=$'\t' read -r ssid strength security active; do
      known=false
      if grep -Fxq -- "$ssid" <<< "$known_wifi"; then
        known=true
      fi

      jq -cn \
        --arg ssid "$ssid" \
        --argjson strength "$strength" \
        --arg security "$security" \
        --argjson active "$active" \
        --argjson known "$known" \
        '{ssid: $ssid, strength: $strength, security: $security,
          active: ($active == 1), known: $known}'
    done \
  | jq -sc 'sort_by(if .active then 0 else 1 end, -.strength, .ssid)'
