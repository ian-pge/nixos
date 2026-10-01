#!/usr/bin/env bash
set -euo pipefail

picker_dir=$(mktemp -d -t beeper-file-picker.XXXXXX)
cleanup() {
  rm -f -- "$picker_dir/selection"
  rmdir -- "$picker_dir"
}
trap cleanup EXIT

# A separate Ghostty process waits for Yazi even if another terminal is open.
# Reuse the usual file-manager class: Hyprland centers it at 1000 x 600, floating.
# Paths are passed as arguments, never interpolated into a shell command.
if ! ghostty --gtk-single-instance=false --class=dev.me.file --title="Attach a file" -e \
  yazi --chooser-file="$picker_dir/selection" "${HOME:-/}" >/dev/null 2>&1; then
  printf '%s\n' 'Could not open Yazi in Ghostty.' >&2
  exit 1
fi

if [[ ! -s "$picker_dir/selection" ]]; then
  printf '%s\n' '{"paths":[]}'
  exit 0
fi

# Preserve Yazi's selection order and encode names without shell evaluation.
jq -Rs '
  split("\n") | if .[-1] == "" then .[:-1] else . end
  | {paths: .}
' "$picker_dir/selection"
