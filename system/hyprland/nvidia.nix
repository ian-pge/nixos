{config, ...}: {
  nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };

  boot.kernelParams = ["nvidia-drm.modeset=1"];

  # Enable OpenGL
  hardware.opengl.enable = true;

  xserver = {
    enable = false;
    videoDrivers = ["nvidia"];
  };
}
