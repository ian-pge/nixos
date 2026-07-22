#!/usr/bin/env bash
set -u

ssid=${1:?missing SSID}
IFS= read -r password

# --ask reads the secret from stdin, keeping it out of Quickshell's process
# command and out of nmcli's command-line arguments.
printf '%s\n' "$password" | nmcli --ask --wait 15 device wifi connect "$ssid"
