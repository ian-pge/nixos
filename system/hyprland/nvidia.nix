{config, ...}: {
  hardware = {
    # Enable OpenGL
    opengl.enable = true;
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.latest;
    };
  };
  services.xserver.videoDrivers = ["nvidia"];
  boot.kernelParams = ["nvidia-drm.modeset=1"];
}
