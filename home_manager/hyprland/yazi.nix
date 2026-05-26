{ pkgs, ... }: let
  yaziOpen = pkgs.writeShellScriptBin "yazi-open" ''
    tmp="$(${pkgs.coreutils}/bin/mktemp -t yazi-chooser.XXXXXX)"

    ${pkgs.yazi}/bin/yazi "$@" --chooser-file="$tmp"

    if [ -s "$tmp" ]; then
      opened_file="$(${pkgs.coreutils}/bin/head -n 1 "$tmp")"
      ${pkgs.util-linux}/bin/setsid ${pkgs.coreutils}/bin/env \
        -u NIXOS_XDG_OPEN_USE_PORTAL \
        -u GTK_USE_PORTAL \
        ${pkgs.xdg-utils}/bin/xdg-open "$opened_file" >/dev/null 2>&1 &
    fi

    ${pkgs.coreutils}/bin/rm -f -- "$tmp"
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
