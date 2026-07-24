set -euo pipefail

flake_dir="${NIXOS_FLAKE_DIR:-$HOME/.config/nixos}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/top-bar"
cache_file="$cache_dir/updates.json"
lock_file="$cache_dir/updates.lock"
backup_dir=""
had_lockfile=false
rollback_pending=false

wait_before_close() {
  printf '\n'
  read -r -p "Press Enter to close..." _
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
  if [[ -n "$backup_dir" ]]; then
    rm -rf "$backup_dir"
  fi
}
trap cleanup EXIT

mkdir -p "$cache_dir"
exec 9>"$lock_file"
flock 9

printf '📦 Starting NixOS update...\n'
cd "$flake_dir"

backup_dir=$(mktemp -d)
if [[ -f flake.lock ]]; then
  cp -p flake.lock "$backup_dir/flake.lock"
  had_lockfile=true
fi
rollback_pending=true

if ! nix flake update; then
  restore_lockfile
  rollback_pending=false
  flock -u 9
  printf '\n❌ Lockfile update failed. The previous lockfile was restored.\n'
  wait_before_close
  exit 1
fi

if ! nh os switch; then
  restore_lockfile
  rollback_pending=false
  flock -u 9
  printf '\n❌ System rebuild failed. The previous lockfile was restored.\n'
  wait_before_close
  exit 1
fi

rollback_pending=false
temporary=$(mktemp "$cache_dir/updates.XXXXXX")
jq -cn '{state: "ok", hasUpdates: false, message: "Just updated",
  updates: [], checkedAt: (now | floor)}' >"$temporary"
mv "$temporary" "$cache_file"
flock -u 9

qs --config top-bar ipc call topbar refreshNix || true

printf '\n✅ Update complete. Quickshell status refreshed.\n'
wait_before_close
