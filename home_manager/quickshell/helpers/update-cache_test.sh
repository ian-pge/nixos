#!/usr/bin/env bash
set -euo pipefail

helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
export PATH="$fake_bin:$PATH"

bash "$helpers_dir/update-checker.sh" force >/dev/null
[[ "$(cat "$FAKE_NIX_COUNT")" == 1 ]]
[[ -f "$cache_home/quickshell/top-bar/update-candidate.lock" ]]
[[ -f "$cache_home/quickshell/top-bar/update-candidate.json" ]]

installer_output="$test_root/installer-output"
if bash "$helpers_dir/update-installer.sh" >"$installer_output"; then
  printf 'installer unexpectedly succeeded with the failing fake nh\n' >&2
  exit 1
fi
grep -Fq 'Reusing the lockfile already checked by the update widget.' \
  "$installer_output"
[[ "$(cat "$FAKE_NIX_COUNT")" == 1 ]]
[[ "$(jq -r '.nodes.nixpkgs.locked.rev' "$flake_dir/flake.lock")" == old ]]

printf '\n# changed after checking\n' >>"$flake_dir/flake.nix"
if bash "$helpers_dir/update-installer.sh" >"$installer_output"; then
  printf 'installer unexpectedly succeeded with the failing fake nh\n' >&2
  exit 1
fi
if grep -Fq 'Reusing the lockfile already checked by the update widget.' \
    "$installer_output"; then
  printf 'installer reused a stale candidate lock\n' >&2
  exit 1
fi
[[ "$(cat "$FAKE_NIX_COUNT")" == 2 ]]
[[ ! -e "$cache_home/quickshell/top-bar/update-candidate.lock" ]]
[[ ! -e "$cache_home/quickshell/top-bar/update-candidate.json" ]]
[[ "$(jq -r '.nodes.nixpkgs.locked.rev' "$flake_dir/flake.lock")" == old ]]

printf 'update cache integration tests passed\n'
