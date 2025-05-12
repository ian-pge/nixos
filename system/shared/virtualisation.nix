{pkgs, ...}: {
  programs.virt-manager.enable = true;

  users.groups.libvirtd.members = ["ian"];

  virtualisation.libvirtd.enable = true;

  virtualisation.spiceUSBRedirection.enable = true;

  environment.systemPackages = with pkgs; [
    quickemu
  ];
}
