{pkgs, ...}: {
  # environment.systemPackages = [pkgs.gazelle-tui];
  networking = {
    useDHCP = false; # NM will do DHCP itself
    networkmanager = {
      enable = true;
      # wifi.backend = "iwd";      # make NM talk to iwd instead of wpa_supplicant
    };
  };

  users.users."ian".extraGroups = ["networkmanager"];
}
