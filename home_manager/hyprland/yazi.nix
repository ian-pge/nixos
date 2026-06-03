{ pkgs, ... }: let
  yaziOpen = pkgs.writeShellScriptBin "yazi-open" ''
    # Debug logging used while fixing this wrapper; left here for easy re-enable:
    # log_dir="$HOME/.cache/yazi-open"
    # mkdir -p "$log_dir"
    # log_file="$log_dir/debug.log"
    # exec 3>>"$log_file"
    # log() { printf '%s [pid=%s] %s\n' "$(date --iso-8601=ns)" "$$" "$*" >&3; }

    tmp="$(${pkgs.coreutils}/bin/mktemp -t yazi-chooser.XXXXXX)"
    cleanup() {
      ${pkgs.coreutils}/bin/rm -f -- "$tmp"
    }
    trap cleanup EXIT

    ${pkgs.yazi}/bin/yazi "$@" --chooser-file="$tmp"

    if [ -s "$tmp" ]; then
      opened_file="$(${pkgs.coreutils}/bin/head -n 1 "$tmp")"
      unit="yazi-zed-$(${pkgs.coreutils}/bin/date +%s)-$$.scope"

      # UWSM is the native launcher for this Hyprland session; it creates a
      # user-systemd scope with the right graphical session environment.
      ${pkgs.uwsm}/bin/uwsm app -u "$unit" -S both -- \
        ${pkgs.zed-editor}/bin/zeditor --new "$opened_file" >/dev/null 2>&1
    fi
  '';
in {
  home.packages = [ yaziOpen ];

  programs.yazi = {
    enable = true;
    shellWrapperName = "yy";
    enableFishIntegration = true;

    plugins = {
      mount = pkgs.yaziPlugins.mount;
    };

    keymap.mgr.prepend_keymap = [
      {
        # In picker mode, Yazi exits when the normal `open` action fires.
        # Keep `o` as a non-picker open action so Yazi stays open.
        on = "o";
        run = ''shell --orphan -- ${pkgs.coreutils}/bin/env -u NIXOS_XDG_OPEN_USE_PORTAL -u GTK_USE_PORTAL ${pkgs.xdg-utils}/bin/xdg-open "$0"'';
        desc = "Open hovered item with default app without quitting";
      }
      {
        on = "M";
        run = "plugin mount";
        desc = "Open mount manager";
      }
    ];
  };
}
