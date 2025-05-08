{
  programs.steam = {
    enable = true;
    extraPkgs = pkgs: with pkgs.pkgsi686Linux; [networkmanager];
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };
}
