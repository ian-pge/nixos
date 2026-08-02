{
  helpers,
  lib,
  pkgs,
}: let
  inherit (helpers) mkLuaArgs mkLuaInline toLua;

  xwaylandSetupCommand = "${pkgs.bash}/bin/bash -c ${lib.escapeShellArg ''
    for ((attempt = 0; attempt < 100; attempt++)); do
      if ${pkgs.xhost}/bin/xhost +local: >/dev/null 2>&1; then
        exec ${pkgs.coreutils}/bin/env LC_ALL=C ${pkgs.xrdb}/bin/xrdb -merge /home/ian/.Xresources
      fi

      ${pkgs.coreutils}/bin/sleep 0.1
    done

    echo "Timed out waiting for XWayland; xhost/xrdb were not applied" >&2
    exit 1
  ''}";
in {
  on = mkLuaArgs [
    "hyprland.start"
    (mkLuaInline ''
      function()
        hl.exec_cmd("uwsm finalize")
        hl.exec_cmd(${toLua xwaylandSetupCommand})
      end
    '')
  ];
}
