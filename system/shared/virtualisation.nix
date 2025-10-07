{pkgs, ...}: {
  programs.virt-manager.enable = true;

  users.users."ian".extraGroups = ["libvirtd"];

  virtualisation.spiceUSBRedirection.enable = true;

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };
}
