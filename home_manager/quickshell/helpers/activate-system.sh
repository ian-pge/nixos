# shellcheck shell=bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'usage: quickshell-update-activator SYSTEM_PATH\n' >&2
  exit 2
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  printf 'quickshell-update-activator must run as root\n' >&2
  exit 1
fi

system_path="$(readlink -f -- "$1")"
case "$system_path" in
  /nix/store/*-nixos-system-*) ;;
  *)
    printf 'refusing non-system path: %s\n' "$system_path" >&2
    exit 1
    ;;
esac

switch_script="$system_path/bin/switch-to-configuration"
for required_path in \
    "$switch_script" \
    "$system_path/nixos-version" \
    "$system_path/init" \
    "$system_path/sw/bin"; do
  if [[ ! -e "$required_path" ]]; then
    printf 'incomplete NixOS closure: %s is missing\n' "$required_path" >&2
    exit 1
  fi
done

if [[ "$(stat -c %u -- "$system_path")" -ne 0 ]]; then
  printf 'refusing a system path not owned by root\n' >&2
  exit 1
fi

# Match nixos-rebuild's native switch sequence while keeping the whole
# privileged operation behind one direct run0 call: register the generation
# first, then activate it. Calling `test` followed by `boot` is not equivalent
# to `switch` and can leave runtime wrappers pointing at a temporary directory.
export NIXOS_INSTALL_BOOTLOADER=0
nix-env -p /nix/var/nix/profiles/system --set "$system_path"
"$switch_script" switch
