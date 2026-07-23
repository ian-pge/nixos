set -euo pipefail

flake_dir="${NIXOS_FLAKE_DIR:-$HOME/.config/nixos}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/top-bar"
cache_file="$cache_dir/updates.json"

wait_before_close() {
  printf '\n'
  read -r -p "Press Enter to close..." _
}

printf '📦 Starting NixOS update...\n'
cd "$flake_dir"

if ! nix flake update; then
  printf '\n❌ Lockfile update failed.\n'
  wait_before_close
  exit 1
fi

if ! nh os switch; then
  printf '\n❌ System rebuild failed.\n'
  wait_before_close
  exit 1
fi

mkdir -p "$cache_dir"
temporary=$(mktemp "$cache_dir/updates.XXXXXX")
jq -cn '{hasUpdates: false, message: "Just updated", updates: [],
  checkedAt: (now | floor)}' >"$temporary"
mv "$temporary" "$cache_file"

qs --config top-bar ipc call topbar refreshNix || true

printf '\n✅ Update complete. Quickshell status refreshed.\n'
wait_before_close
