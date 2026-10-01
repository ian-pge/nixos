#!/usr/bin/env bash
set -euo pipefail

picker_dir=$(mktemp -d -t beeper-file-picker.XXXXXX)
cleanup() {
  rm -f -- "$picker_dir/selection"
  rmdir -- "$picker_dir"
}
trap cleanup EXIT

# A separate Ghostty process waits for Yazi even if another terminal is open.
# Paths are passed as arguments, never interpolated into a shell command.
if ! ghostty --gtk-single-instance=false --title="Attach a file" -e \
  yazi --chooser-file="$picker_dir/selection" "${HOME:-/}" >/dev/null 2>&1; then
  printf '%s\n' 'Could not open Yazi in Ghostty.' >&2
  exit 1
fi

if [[ ! -s "$picker_dir/selection" ]]; then
  printf '%s\n' '{"path":""}'
  exit 0
fi

# The messenger currently supports one attachment per message. Reject a
# multi-selection explicitly instead of silently dropping selected files.
jq -Rs '
  split("\n") | if .[-1] == "" then .[:-1] else . end
  | if length == 1 then {path: .[0]}
    else error("Choose one file per message.") end
' "$picker_dir/selection"
