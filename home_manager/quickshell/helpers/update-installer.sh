# shellcheck shell=bash
set -uo pipefail

flake_dir="${NIXOS_FLAKE_DIR:-$HOME/.config/nixos}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/top-bar"
cache_file="$cache_dir/updates.json"
lock_file="$cache_dir/updates.lock"
result_link="$cache_dir/update-result"
candidate_lock="$cache_dir/update-candidate.lock"
candidate_meta="$cache_dir/update-candidate.json"
backup_dir=""
had_lockfile=false
rollback_pending=false

flake_state_hash() {
  local flake_hash lock_hash="missing"
  flake_hash="$(sha256sum "$flake_dir/flake.nix" | cut -d' ' -f1)"
  if [[ -f "$flake_dir/flake.lock" ]]; then
    lock_hash="$(sha256sum "$flake_dir/flake.lock" | cut -d' ' -f1)"
  fi
  printf 'flake.nix=%s\nflake.lock=%s\n' "$flake_hash" "$lock_hash" \
    | sha256sum | cut -d' ' -f1
}

use_checked_lock() {
  local expected_base expected_candidate current_base actual_candidate
  [[ -f "$candidate_lock" && -f "$candidate_meta" ]] || return 1
  jq -e '
    .version == 1
    and (.baseHash | type == "string")
    and (.candidateHash | type == "string")
  ' "$candidate_meta" >/dev/null 2>&1 || return 1
  jq -e '.nodes | type == "object"' "$candidate_lock" \
    >/dev/null 2>&1 || return 1

  expected_base="$(jq -r '.baseHash' "$candidate_meta")"
  expected_candidate="$(jq -r '.candidateHash' "$candidate_meta")"
  current_base="$(flake_state_hash)"
  actual_candidate="$(sha256sum "$candidate_lock" | cut -d' ' -f1)"
  [[ "$current_base" == "$expected_base" \
      && "$actual_candidate" == "$expected_candidate" ]] || return 1

  cp "$candidate_lock" "$flake_dir/flake.lock"
}

clear_candidate() {
  rm -f "$candidate_lock" "$candidate_meta"
}

# Quickshell consumes these records without showing them in the console. All
# other output remains human-readable and is streamed as update logs.
emit_event() {
  local phase="$1"
  local message="$2"
  printf '@@QS_UPDATE@@%s\n' "$(jq -cn \
    --arg phase "$phase" --arg message "$message" \
    '{phase: $phase, message: $message}')"
}

emit_changes_event() {
  local phase="$1"
  local message="$2"
  local summary="$3"
  printf '@@QS_UPDATE@@%s\n' "$(jq -cn \
    --arg phase "$phase" --arg message "$message" --argjson summary "$summary" \
    '{phase: $phase, message: $message, changes: $summary.changes,
      counts: $summary.counts, total: $summary.total}')"
}

restore_lockfile() {
  if [[ "$had_lockfile" == true ]]; then
    cp -p "$backup_dir/flake.lock" "$flake_dir/flake.lock"
  else
    rm -f "$flake_dir/flake.lock"
  fi
}

cleanup() {
  if [[ "$rollback_pending" == true ]]; then
    restore_lockfile
  fi
  rm -f "$result_link"
  if [[ -n "$backup_dir" ]]; then
    rm -rf "$backup_dir"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail_update() {
  local message="$1"
  printf '\n❌ %s\n' "$message"
  emit_event "error" "$message"
  exit 1
}

mkdir -p "$cache_dir"
exec 9>"$lock_file"
if ! flock -w 300 9; then
  fail_update "The update check did not finish in time."
fi

# Merge stderr into stdout so QML receives a single ordered line stream.
exec 2>&1

cd "$flake_dir" || fail_update "Unable to open the NixOS configuration."
backup_dir="$(mktemp -d)"
if [[ -f flake.lock ]]; then
  cp -p flake.lock "$backup_dir/flake.lock"
  had_lockfile=true
fi
rollback_pending=true

emit_event "updating" "Updating flake inputs"
printf '📦 Updating flake inputs...\n\n'
if use_checked_lock; then
  printf '✓ Reusing the lockfile already checked by the update widget.\n'
else
  clear_candidate
  if ! nix flake update; then
    fail_update "Lockfile update failed. The previous lockfile was restored."
  fi
fi

emit_event "building" "Building the new NixOS configuration"
printf '\n🔨 Building the new NixOS configuration...\n\n'
rm -f "$result_link"
if ! nh os build \
    --out-link "$result_link" \
    --diff never \
    --no-nom \
    "$flake_dir"; then
  fail_update "System build failed. The previous lockfile was restored."
fi

result_path="$(readlink -f "$result_link" 2>/dev/null || true)"
if [[ "$result_path" != /nix/store/* \
    || ! -x "$result_path/bin/switch-to-configuration" ]]; then
  fail_update "The build finished without a valid NixOS system result."
fi

if ! changes_json="$(quickshell-update-diff /run/current-system "$result_path")"; then
  fail_update "The build succeeded, but its package changes could not be summarized."
fi

emit_changes_event "awaitingActivation" "Package changes" "$changes_json"

action=""
while [[ "$action" != "activate" ]]; do
  if ! IFS= read -r action; then
    fail_update "The update console closed before activation."
  fi
done

emit_event "activating" "Waiting for authorization"
printf '\n🔐 Requesting authorization...\n\n'
activator_path="${QS_UPDATE_ACTIVATOR:-}"
if [[ "$activator_path" != /nix/store/* \
    || ! -x "$activator_path" ]]; then
  fail_update "The immutable activation helper is unavailable."
fi
elevator_path="${QS_UPDATE_ELEVATOR:-}"
if [[ "$elevator_path" != /nix/store/*/bin/run0 \
    || ! -x "$elevator_path" ]]; then
  fail_update "The systemd authorization helper is unavailable."
fi
if ! "$elevator_path" --pipe "$activator_path" "$result_path"; then
  fail_update "System activation failed. The previous lockfile was restored."
fi

rollback_pending=false
clear_candidate
temporary="$(mktemp "$cache_dir/updates.XXXXXX")"
jq -cn '{state: "ok", hasUpdates: false, message: "Just updated",
  updates: [], checkedAt: (now | floor)}' >"$temporary"
mv "$temporary" "$cache_file"

qs --config top-bar ipc call topbar refreshNix || true

printf '\n✅ NixOS update and activation complete.\n'
emit_event "success" "NixOS is up to date"
