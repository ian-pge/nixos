{
  config,
  lib,
  ...
}: let
  # UWSM needs these before the compositor starts; reuse Home Manager's values.
  cursorEnv = names: config.lib.shell.exportAll (lib.getAttrs names config.home.sessionVariables);
in {
  xdg.configFile = {
    "uwsm/env".text = ''
      export EDITOR=zeditor
      export TERMINAL=ghostty
      export BROWSER=google-chrome-stable

      ${cursorEnv ["XCURSOR_THEME" "XCURSOR_SIZE"]}
      export GTK_USE_PORTAL=1
      export ELECTRON_OZONE_PLATFORM_HINT=wayland

      # NVIDIA tweaks
      export LIBVA_DRIVER_NAME=nvidia
      export GBM_BACKEND=nvidia-drm
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
    '';

    "uwsm/env-hyprland".text =
      if config.home.pointerCursor.hyprcursor.enable
      then cursorEnv ["HYPRCURSOR_THEME" "HYPRCURSOR_SIZE"]
      else ''
        unset HYPRCURSOR_THEME HYPRCURSOR_SIZE
      '';
  };
}
