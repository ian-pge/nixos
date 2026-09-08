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

# Register the generation and make it the boot default without changing the
# running session.  In particular, do not use `switch` here: Home Manager can
# restart Quickshell during a live activation and kill the update process that
# is coordinating this privileged helper.
export NIXOS_INSTALL_BOOTLOADER=0
system_profile=/nix/var/nix/profiles/system
previous_system="$(readlink -f -- "$system_profile" 2>/dev/null || true)"

nix-env -p "$system_profile" --set "$system_path"
if "$switch_script" boot; then
  exit 0
else
  activation_status=$?
fi

printf 'failed to install the new boot generation; restoring the previous profile\n' >&2

if [[ "$previous_system" == /nix/store/*-nixos-system-* \
    && -x "$previous_system/bin/switch-to-configuration" ]]; then
  nix-env -p "$system_profile" --set "$previous_system" || true
  "$previous_system/bin/switch-to-configuration" boot || true
fi

exit "$activation_status"
