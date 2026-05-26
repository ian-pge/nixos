{
  programs.mpv = {
    enable = true;
    config = {
      # --- decoding ---
      hwdec = "nvdec"; # fastest on NVIDIA ≥ 515

      # --- rendering ---
      vo = "gpu-next"; # async renderer fixes micro-stutter
      "gpu-api" = "vulkan";
    };
  };
}
