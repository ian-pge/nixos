{
  services.avahi = {
    enable = true; # start avahi-daemon
    nssmdns = true; # let glibc resolve “*.local” host names
    openFirewall = true; # automatically open UDP/TCP 5353
  };
}
