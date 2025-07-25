{
  services.flatpak.packages = [
    {
      appId = "com.bambulab.BambuStudio";
      origin = "flathub";
    }
  ];

  services.flatpak.overrides = {
    "com.bambulab.BambuStudio".Environment = {
      __GLX_VENDOR_LIBRARY_NAME = "mesa";
      __EGL_VENDOR_LIBRARY_FILENAMES = "/usr/lib/x86_64-linux-gnu/GL/default/share/glvnd/egl_vendor.d/50_mesa.json"; # adjust if your runtime uses a different path
      MESA_LOADER_DRIVER_OVERRIDE = "zink";
      GALLIUM_DRIVER = "zink";
      WEBKIT_DISABLE_DMABUF_RENDERER = "1";
      WEBKIT_DISABLE_COMPOSITING_MODE = "1";
      WEBKIT_FORCE_COMPOSITING_MODE = "1";
    };
  };
}
