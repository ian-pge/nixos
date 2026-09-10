#!/usr/bin/env bash
set -euo pipefail

helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
fake_bin="$test_root/bin"
mkdir -p "$fake_bin" "$test_root/cache"

printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >"$FAKE_NH_ARGS"' \
  'printf "native nh output\n"' >"$fake_bin/nh"
printf '%s\n' '#!/usr/bin/env bash' \
  'count=0' \
  '[[ -f "$FAKE_DF_COUNT" ]] && count="$(cat "$FAKE_DF_COUNT")"' \
  'count=$((count + 1))' \
  'printf "%s\n" "$count" >"$FAKE_DF_COUNT"' \
  'printf "Avail\n"' \
  'if ((count == 1)); then printf "1000000000\n"; else printf "3500000000\n"; fi' \
  >"$fake_bin/df"
chmod +x "$fake_bin/nh" "$fake_bin/df"

export PATH="$fake_bin:$PATH"
export XDG_CACHE_HOME="$test_root/cache"
export QS_CLEAN_ELEVATOR="$(readlink -f /run/current-system)/sw/bin/run0"
export FAKE_NH_ARGS="$test_root/nh-args"
export FAKE_DF_COUNT="$test_root/df-count"

output="$(bash "$helpers_dir/clean-installer.sh")"
grep -Fq -- "--elevation-strategy $QS_CLEAN_ELEVATOR clean all" \
  "$FAKE_NH_ARGS"
grep -Fq 'native nh output' "$XDG_CACHE_HOME/quickshell/top-bar/clean.log"
if grep -Fq 'native nh output' <<<"$output"; then
  printf 'native nh output leaked into the Quickshell stream\n' >&2
  exit 1
fi
grep -Fq 'Cleanup complete — 2.4GiB reclaimed' <<<"$output"
grep -Fq '"phase":"success"' <<<"$output"

printf 'clean installer integration tests passed\n'
