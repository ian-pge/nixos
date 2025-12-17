{
  services.tailscale.enable = true;
  networking.extraHosts = ''
    192.168.100.30 git.lab.icta
  '';
}
