{
  programs.mpv = {
    enable = true;
    config = {
      # --- decoding ---
      hwdec = "nvdec"; # fastest on NVIDIA ≥ 515
      "vd-lavc-threads" = "1"; # GPU does the decoding, extra CPU threads unused

      # --- rendering ---
      vo = "gpu-next"; # async renderer fixes micro-stutter
      "gpu-api" = "vulkan";
      "gpu-context" = "wayland"; # swap to x11egl if you still use X11
      profile = "gpu-hq";

      # --- timing / smoothness ---
      "video-sync" = "display-resample"; # tie frame-timing to the monitor
      interpolation = "yes"; # optional: synth middle frames
      tscale = "oversample";
    };
  };
}
