{
  services.avahi = {
    enable = true;
    nssmdns = true;
    openFirewall = true;
  };
  # Discovery + LAN mode ports commonly involved
  networking.firewall.allowedUDPPorts = [5353 1990 2021];
  networking.firewall.allowedTCPPorts = [8883 1883 21];
  networking.firewall.allowedTCPPortRanges = [
    {
      from = 50000;
      to = 50100;
    }
  ];
}
