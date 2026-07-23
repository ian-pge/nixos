set -euo pipefail

flake_dir="${NIXOS_FLAKE_DIR:-$HOME/.config/nixos}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/top-bar"
cache_file="$cache_dir/updates.json"
lock_file="$cache_dir/updates.lock"
max_age=1800

mkdir -p "$cache_dir"

write_status() {
  local updates_json=$1
  local message=$2
  local temporary
  temporary=$(mktemp "$cache_dir/updates.XXXXXX")

  jq -cn \
    --argjson updates "$updates_json" \
    --arg message "$message" \
    '{hasUpdates: ($updates | length > 0), message: $message,
      updates: $updates, checkedAt: (now | floor)}' >"$temporary"
  mv "$temporary" "$cache_file"
}

check_updates() (
  local temporary_dir update_output updates_tsv updates_json count
  temporary_dir=$(mktemp -d)
  trap 'rm -rf "$temporary_dir"' EXIT

  cp "$flake_dir/flake.nix" "$temporary_dir/"
  if [[ -f "$flake_dir/flake.lock" ]]; then
    cp "$flake_dir/flake.lock" "$temporary_dir/"
  fi

  if ! update_output=$(nix flake update --flake "$temporary_dir" 2>&1); then
    write_status '[]' "Unable to check for updates"
    return
  fi

  updates_tsv=$(awk '
    /Updated input/ {
      if (match($0, /\047[^\047]+\047/))
        name = substr($0, RSTART + 1, RLENGTH - 2)
    }
    /→/ && name != "" {
      date = "unknown"
      if (match($0, /\([0-9]{4}-[0-9]{2}-[0-9]{2}\)/))
        date = substr($0, RSTART + 1, RLENGTH - 2)
      print name "\t" date
      name = ""
    }
  ' <<<"$update_output")

  updates_json=$(printf '%s\n' "$updates_tsv" | jq -R -s '
    split("\n")
    | map(select(length > 0) | split("\t")
      | {name: .[0], date: (.[1] // "unknown")})
  ')
  count=$(jq 'length' <<<"$updates_json")

  if ((count > 0)); then
    write_status "$updates_json" "$count update(s) available"
  else
    write_status '[]' "System is up to date"
  fi
)

cache_is_fresh() {
  [[ -f "$cache_file" ]] || return 1
  local current_time file_time
  current_time=$(date +%s)
  file_time=$(stat -c %Y "$cache_file")
  ((current_time - file_time < max_age))
}

exec 9>"$lock_file"

if [[ "${1:-}" == "force" ]]; then
  flock 9
  check_updates
elif ! cache_is_fresh; then
  flock 9
  if ! cache_is_fresh; then
    check_updates
  fi
fi

if [[ -f "$cache_file" ]]; then
  cat "$cache_file"
else
  jq -cn '{hasUpdates: false, message: "Checking for updates…",
    updates: [], checkedAt: null}'
fi
