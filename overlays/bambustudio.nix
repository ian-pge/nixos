final: prev: {
  bambu-studio = prev.bambu-studio.overrideAttrs (old: {
    # version = "v02.00.03.54";
    # src = final.fetchFromGitHub {
    #   owner = "bambulab";
    #   repo = "BambuStudio";
    #   rev = "v02.00.03.54";
    #   hash = "sha256-DUrlmeH3XJmke6VOwC7HREONQMIhg3wFYw7QTndY2/Y=";
    # };

    # version = "01.00.01.50";
    # src = final.fetchFromGitHub {
    #   owner = "bambulab";
    #   repo = "BambuStudio";
    #   rev = "v01.00.01.50";
    #   hash = "sha256-7mkrPl2CQSfc1lRjl1ilwxdYcK5iRU//QGKmdCicK30=";
    # };

    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.makeWrapper];
    postInstall =
      (old.postInstall or "")
      + ''
        wrapProgram $out/bin/bambu-studio \
          --set __GLX_VENDOR_LIBRARY_NAME mesa \
          --set __EGL_VENDOR_LIBRARY_FILENAMES /run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json \
          --set MESA_LOADER_DRIVER_OVERRIDE zink \
          --set GALLIUM_DRIVER zink \
          --set WEBKIT_DISABLE_DMABUF_RENDERER 1
      '';
  });
}
