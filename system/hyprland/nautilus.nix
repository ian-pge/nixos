{pkgs, ...}: {
  services.gvfs.enable = true; # for the trash to work
  environment.systemPackages = pkgs.nautilus;
}
