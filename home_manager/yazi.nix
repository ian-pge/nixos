{
  config,
  pkgs,
  ...
}: let
  # Both the chooser and the in-Yazi `o` action share these application rules.
  yaziOpenFiles = pkgs.writeShellScript "yazi-open-files" ''
    set -eu
    launch_index=0

    run_in_uwsm() {
      launch_index=$((launch_index + 1))
      unit="yazi-$1-$(${pkgs.coreutils}/bin/date +%s)-$$-$launch_index.scope"
      shift

      # UWSM is the native launcher for this Hyprland session; it creates a
      # user-systemd scope with the right graphical session environment.
      ${pkgs.util-linux}/bin/setsid -f ${pkgs.uwsm}/bin/uwsm app -u "$unit" -S both -- "$@" >/dev/null 2>&1
    }

    open_with_zed() {
      run_in_uwsm zed ${config.programs.zed-editor.package}/bin/zeditor --new "$1"
    }

    open_with_default_app() {
      case "$2" in
        image/*)
          run_in_uwsm oculante ${pkgs.oculante}/bin/oculante "$1"
          ;;
        application/pdf)
          run_in_uwsm zathura ${pkgs.zathura}/bin/zathura "$1"
          ;;
        video/*)
          run_in_uwsm mpv ${pkgs.mpv}/bin/mpv "$1"
          ;;
        *)
          run_in_uwsm xdg-open \
            ${pkgs.coreutils}/bin/env -u NIXOS_XDG_OPEN_USE_PORTAL -u GTK_USE_PORTAL \
            ${pkgs.xdg-utils}/bin/xdg-open "$1"
          ;;
      esac
    }

    is_code_file() {
      case "$2" in
        text/*|application/json|application/*+json|application/xml|application/*+xml|application/x-yaml|application/toml|application/x-shellscript)
          return 0
          ;;
      esac

      case "$1" in
        *.astro|*.c|*.cc|*.clj|*.cljs|*.conf|*.cpp|*.cs|*.css|*.dart|*.diff|*.dockerfile|*.elm|*.ex|*.exs|*.fish|*.go|*.h|*.hpp|*.hs|*.html|*.java|*.js|*.jsx|*.kt|*.lua|*.md|*.nix|*.patch|*.php|*.pl|*.prisma|*.py|*.r|*.rb|*.rs|*.scss|*.sh|*.sql|*.svelte|*.swift|*.tf|*.toml|*.ts|*.tsx|*.vue|*.yaml|*.yml|*.zig)
          return 0
          ;;
      esac

      return 1
    }

    for path in "$@"; do
      [ -n "$path" ] || continue
      if [ -d "$path" ]; then
        open_with_zed "$path"
        continue
      fi
      mime="$(${pkgs.file}/bin/file --brief --mime-type -- "$path" 2>/dev/null || true)"
      if is_code_file "$path" "$mime"; then
        open_with_zed "$path"
      else
        open_with_default_app "$path" "$mime"
      fi
    done
  '';

  yaziOpen = pkgs.writeShellScriptBin "yazi-open" ''
    set -eu
    tmp="$(${pkgs.coreutils}/bin/mktemp -t yazi-chooser.XXXXXX)"
    cleanup() {
      ${pkgs.coreutils}/bin/rm -f -- "$tmp"
    }
    trap cleanup EXIT

    ${pkgs.yazi}/bin/yazi "$@" --chooser-file="$tmp"

    if [ -s "$tmp" ]; then
      mapfile -t selected < "$tmp"
      ${yaziOpenFiles} "''${selected[@]}"
    fi
  '';
in {
  home.packages = [yaziOpen];

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
        run = "shell --orphan -- ${yaziOpenFiles} %h";
        desc = "Open hovered item without quitting";
      }
      {
        on = "M";
        run = "plugin mount";
        desc = "Open mount manager";
      }
    ];
  };
}
