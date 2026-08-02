{...}: {
  xdg.configFile = {
    "uwsm/env".text = ''
      export EDITOR=zeditor
      export TERMINAL=ghostty
      export BROWSER=google-chrome-stable

      export XCURSOR_THEME=catppuccin-macchiato-dark-cursors
      export XCURSOR_SIZE=24
      export GTK_USE_PORTAL=1
      export ELECTRON_OZONE_PLATFORM_HINT=wayland

      # NVIDIA tweaks
      export LIBVA_DRIVER_NAME=nvidia
      export GBM_BACKEND=nvidia-drm
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
    '';

    "uwsm/env-hyprland".text = ''
      export HYPRCURSOR_THEME=catppuccin-macchiato-dark-cursors
      export HYPRCURSOR_SIZE=24
    '';
  };
}
