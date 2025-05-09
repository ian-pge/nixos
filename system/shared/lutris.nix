{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    lutris
    protonup-qt
    wine
    winetricks
  ];
}
