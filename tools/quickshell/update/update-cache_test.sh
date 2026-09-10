#!/usr/bin/env bash
set -euo pipefail

helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="${QS_UPDATE_CHECKER_BIN:-$helpers_dir/target/debug/quickshell-update-checker}"
installer="${QS_UPDATE_INSTALLER_BIN:-$helpers_dir/target/debug/quickshell-update-installer}"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

flake_dir="$test_root/flake"
cache_home="$test_root/cache"
fake_bin="$test_root/bin"
mkdir -p "$flake_dir" "$cache_home" "$fake_bin"

printf '{ outputs = _: {}; }\n' >"$flake_dir/flake.nix"
jq -cn '{nodes: {
  root: {inputs: {nixpkgs: "nixpkgs"}},
  nixpkgs: {locked: {type: "github", owner: "NixOS", repo: "nixpkgs",
    rev: "old", lastModified: 1}}
}, root: "root", version: 7}' >"$flake_dir/flake.lock"
jq -cn '{nodes: {
  root: {inputs: {nixpkgs: "nixpkgs"}},
  nixpkgs: {locked: {type: "github", owner: "NixOS", repo: "nixpkgs",
    rev: "new", lastModified: 2}}
}, root: "root", version: 7}' >"$test_root/new.lock"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'count=0' \
  '[[ -f "$FAKE_NIX_COUNT" ]] && count="$(cat "$FAKE_NIX_COUNT")"' \
  'printf "%s\n" "$((count + 1))" >"$FAKE_NIX_COUNT"' \
  'target="$PWD"' \
  'while (($#)); do' \
  '  if [[ "$1" == "--flake" ]]; then target="$2"; shift 2; else shift; fi' \
  'done' \
  'cp "$FAKE_NEW_LOCK" "$target/flake.lock"' \
  >"$fake_bin/nix"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$fake_bin/nh"
chmod +x "$fake_bin/nix" "$fake_bin/nh"

export NIXOS_FLAKE_DIR="$flake_dir"
export XDG_CACHE_HOME="$cache_home"
export FAKE_NIX_COUNT="$test_root/nix-count"
export FAKE_NEW_LOCK="$test_root/new.lock"
export QS_CURRENT_SYSTEM_LINK="$test_root/current-system"
export QS_SYSTEM_PROFILE="$test_root/system-profile"
export QS_STORE_DIR="$test_root/store"
export PATH="$fake_bin:$PATH"

"$checker" force >/dev/null
[[ "$(cat "$FAKE_NIX_COUNT")" == 1 ]]
[[ -f "$cache_home/quickshell/top-bar/update-candidate.lock" ]]
[[ -f "$cache_home/quickshell/top-bar/update-candidate.json" ]]
[[ "$(jq -r '.sourceHash | type' \
  "$cache_home/quickshell/top-bar/updates.json")" == string ]]

"$checker" >/dev/null
[[ "$(cat "$FAKE_NIX_COUNT")" == 1 ]]

printf '\n# changed after checking\n' >>"$flake_dir/flake.nix"
"$checker" >/dev/null
[[ "$(cat "$FAKE_NIX_COUNT")" == 2 ]]

installer_output="$test_root/installer-output"
if "$installer" >"$installer_output"; then
  printf 'installer unexpectedly succeeded with the failing fake nh\n' >&2
  exit 1
fi
grep -Fq 'Reusing the lockfile already checked by the update widget.' \
  "$installer_output"
[[ "$(cat "$FAKE_NIX_COUNT")" == 2 ]]
[[ "$(jq -r '.nodes.nixpkgs.locked.rev' "$flake_dir/flake.lock")" == old ]]

printf '\n# changed again after checking\n' >>"$flake_dir/flake.nix"
if "$installer" >"$installer_output"; then
  printf 'installer unexpectedly succeeded with the failing fake nh\n' >&2
  exit 1
fi
if grep -Fq 'Reusing the lockfile already checked by the update widget.' \
    "$installer_output"; then
  printf 'installer reused a stale candidate lock\n' >&2
  exit 1
fi
[[ "$(cat "$FAKE_NIX_COUNT")" == 3 ]]
[[ ! -e "$cache_home/quickshell/top-bar/update-candidate.lock" ]]
[[ ! -e "$cache_home/quickshell/top-bar/update-candidate.json" ]]
[[ "$(jq -r '.nodes.nixpkgs.locked.rev' "$flake_dir/flake.lock")" == old ]]

mkdir -p "$QS_STORE_DIR/current" "$QS_STORE_DIR/target"
ln -s "$QS_STORE_DIR/current" "$QS_CURRENT_SYSTEM_LINK"
ln -s "$QS_STORE_DIR/target" "$QS_SYSTEM_PROFILE"
jq -cn --arg targetSystem "$QS_STORE_DIR/target" \
  '{version: 1, targetSystem: $targetSystem, createdAt: 1}' \
  >"$cache_home/quickshell/top-bar/pending-reboot.json"

status="$("$checker" force)"
[[ "$(jq -r '.state' <<<"$status")" == reboot-required ]]
[[ "$(cat "$FAKE_NIX_COUNT")" == 3 ]]

rm "$QS_CURRENT_SYSTEM_LINK"
ln -s "$QS_STORE_DIR/target" "$QS_CURRENT_SYSTEM_LINK"
"$checker" force >/dev/null
[[ ! -e "$cache_home/quickshell/top-bar/pending-reboot.json" ]]
[[ "$(cat "$FAKE_NIX_COUNT")" == 4 ]]

printf 'update cache integration tests passed\n'
