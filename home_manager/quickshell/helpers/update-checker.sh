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
  local state=${3:-ok}
  local temporary
  temporary=$(mktemp "$cache_dir/updates.XXXXXX")

  jq -cn \
    --argjson updates "$updates_json" \
    --arg message "$message" \
    --arg state "$state" \
    '{state: $state, hasUpdates: ($updates | length > 0),
      message: $message, updates: $updates, checkedAt: (now | floor)}' \
    >"$temporary"
  mv "$temporary" "$cache_file"
}

check_updates() (
  local temporary_dir before_lock updates_json count
  temporary_dir=$(mktemp -d)
  trap 'rm -rf "$temporary_dir"' EXIT

  if [[ ! -f "$flake_dir/flake.nix" ]]; then
    write_status '[]' "Unable to check for updates" error
    return
  fi

  cp "$flake_dir/flake.nix" "$temporary_dir/"
  before_lock="$temporary_dir/before.lock"
  if [[ -f "$flake_dir/flake.lock" ]]; then
    cp "$flake_dir/flake.lock" "$temporary_dir/flake.lock"
    cp "$flake_dir/flake.lock" "$before_lock"
  else
    printf '{"nodes":{},"root":"root","version":7}\n' >"$before_lock"
  fi

  if ! jq -e '.nodes | type == "object"' "$before_lock" \
    >/dev/null 2>&1; then
    write_status '[]' "Unable to check for updates" error
    return
  fi

  if ! nix flake update --flake "$temporary_dir" \
    >"$temporary_dir/update.log" 2>&1; then
    write_status '[]' "Unable to check for updates" error
    return
  fi

  if ! jq -e '.nodes | type == "object"' "$temporary_dir/flake.lock" \
    >/dev/null 2>&1; then
    write_status '[]' "Unable to check for updates" error
    return
  fi

  if ! updates_json=$(jq -n \
    --slurpfile old "$before_lock" \
    --slurpfile new "$temporary_dir/flake.lock" '
      ($old[0].nodes // {}) as $oldNodes
      | ($new[0].nodes // {}) as $newNodes
      | ($new[0].root // "root") as $rootNode
      | ($newNodes[$rootNode].inputs // {}) as $rootInputs
      | (($oldNodes | keys) + ($newNodes | keys) | unique) as $nodeNames
      | [
          $nodeNames[] as $name
          | select($name != $rootNode)
          | select(
              ($oldNodes[$name].locked // null)
              != ($newNodes[$name].locked // null)
            )
          | ($newNodes[$name] // $oldNodes[$name]) as $node
          | ([
              $rootInputs | to_entries[]
              | select(.value == $name) | .key
            ][0] // $name) as $displayName
          | {
              name: $displayName,
              date: (
                if ($node.locked.lastModified // null) == null then
                  "unknown"
                else
                  ($node.locked.lastModified
                    | todateiso8601 | split("T")[0])
                end
              )
            }
        ]
      | sort_by(.name)
    '); then
    write_status '[]' "Unable to check for updates" error
    return
  fi
  count=$(jq 'length' <<<"$updates_json")

  if ((count > 0)); then
    write_status "$updates_json" "$count update(s) available"
  else
    write_status '[]' "System is up to date"
  fi
)

cache_is_fresh() {
  [[ -f "$cache_file" ]] || return 1
  jq -e '
    (.state // "ok") == "ok"
    and (.updates | type == "array")
    and (.checkedAt == null or (.checkedAt | type == "number"))
  ' "$cache_file" >/dev/null || return 1

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
  jq -cn '{state: "checking", hasUpdates: false,
    message: "Checking for updates…", updates: [], checkedAt: null}'
fi
