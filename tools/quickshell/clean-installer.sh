# shellcheck shell=bash
set -uo pipefail

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/top-bar"
lock_file="$cache_dir/updates.lock"
clean_log="$cache_dir/clean.log"
elevator_path="${QS_CLEAN_ELEVATOR:-}"

emit_event() {
  local phase="$1" message="$2"
  printf '@@QS_UPDATE@@%s\n' "$(jq -cn \
    --arg phase "$phase" --arg message "$message" \
    '{phase: $phase, message: $message}')"
}

fail_clean() {
  local message="$1"
  printf '\n❌ %s\n' "$message"
  emit_event "error" "$message"
  exit 1
}

available_bytes() {
  df --output=avail -B1 /nix/store | tail -n 1 | tr -d '[:space:]'
}

mkdir -p "$cache_dir"
exec 9>"$lock_file"
if ! flock -w 300 9; then
  fail_clean "The update check did not finish in time."
fi

# Quickshell consumes the structured markers and renders every other line in
# its integrated console.
exec 2>&1

if [[ "$elevator_path" != /nix/store/*/bin/run0 \
    || ! -x "$elevator_path" ]]; then
  fail_clean "The systemd authorization helper is unavailable."
fi

before_bytes="$(available_bytes)"
[[ "$before_bytes" =~ ^[0-9]+$ ]] \
  || fail_clean "Unable to read the available Nix store space."

emit_event "cleaning" "Cleaning Nix generations and store"
printf '🧹 Running nh clean all...\n'
: >"$clean_log"
if ! NO_COLOR=1 nh --elevation-strategy "$elevator_path" clean all \
    >"$clean_log" 2>&1; then
  printf '\nLast nh output:\n'
  tail -n 30 "$clean_log"
  fail_clean "Nix cleanup failed."
fi

after_bytes="$(available_bytes)"
[[ "$after_bytes" =~ ^[0-9]+$ ]] \
  || fail_clean "Cleanup completed, but the reclaimed space could not be measured."

freed_bytes=$((after_bytes - before_bytes))
if ((freed_bytes < 0)); then
  freed_bytes=0
fi
freed_human="$(numfmt --to=iec-i --suffix=B --format='%.1f' "$freed_bytes")"

printf '\n✅ Cleanup complete — %s reclaimed.\n' "$freed_human"
emit_event "success" "Cleanup complete — $freed_human reclaimed"
